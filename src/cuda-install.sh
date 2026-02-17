#!/bin/bash

# NVIDIA CUDA Toolkit 一键安装脚本
# NVIDIA CUDA Toolkit One-Click Installer

# Author: PEScn @ EM-GeekLab
# Modified: 2026-02-17
# License: Apache-2.0
# GitHub: https://github.com/EM-GeekLab/nvidia-driver-installer
# Supports Debian, Ubuntu, Fedora, RHEL, Rocky Linux, Oracle Linux, SLES, OpenSUSE
# This script need `root` privileges to run, or use `sudo` to run it.

# ==============================================================================
# Usage | 用法
# ==============================================================================
# 1. download the script | 下载脚本
#
#   $ curl -sSL https://raw.githubusercontent.com/EM-GeekLab/nvidia-driver-installer/main/cuda-install.sh -o cuda-install.sh
#
# 2. [Optional] verify the script's content | 【可选】验证脚本内容
#
#   $ cat cuda-install.sh
#
# 3. run the script either as root, or using sudo to perform the installation. | 以 root 权限或使用 sudo 运行脚本进行安装
#
#   $ sudo bash cuda-install.sh
#
# ==============================================================================

set -eo pipefail

readonly SCRIPT_VERSION="2.0"

# Color Definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Exit code definitions
readonly EXIT_SUCCESS=0
readonly EXIT_NO_ROOT=1
readonly EXIT_STATE_DIR_FAILED=3
readonly EXIT_UNSUPPORTED_OS=20
readonly EXIT_UNSUPPORTED_ARCH=22
readonly EXIT_INVALID_ARGS=30
readonly EXIT_INVALID_INSTALL_TYPE=31
readonly EXIT_NETWORK_FAILED=60
readonly EXIT_REPO_ADD_FAILED=71
readonly EXIT_PKG_INSTALL_FAILED=74
readonly EXIT_ROLLBACK_FILE_MISSING=90
readonly EXIT_ROLLBACK_FAILED=91
readonly EXIT_STATE_FILE_CORRUPTED=92
readonly EXIT_USER_CANCELLED=100

# Global variables
AUTO_YES=false
QUIET_MODE=false

# State tracking
STATE_DIR="/var/lib/cuda-installer"
STATE_FILE="$STATE_DIR/install.state"
ROLLBACK_FILE="$STATE_DIR/rollback.list"

# Environment variable support
CUDA_INSTALLER_AUTO_YES=${CUDA_INSTALLER_AUTO_YES:-false}
CUDA_INSTALLER_QUIET=${CUDA_INSTALLER_QUIET:-false}
LANG_CURRENT="${CUDA_INSTALLER_LANG:-zh_CN}"

# ================ Language Packs ==================
# {{LANG_PACKS}}
# ================ Language Packs End ==============


gettext() {
    local msgid="$1"
    local translation=""

    case "$LANG_CURRENT" in
        "zh-cn"|"zh"|"zh_CN")
            translation="${LANG_PACK_ZH_CN[$msgid]:-}"
            ;;
        "en-us"|"en"|"en_US")
            translation="${LANG_PACK_EN_US[$msgid]:-}"
            ;;
        *)
            translation="${LANG_PACK_ZH_CN[$msgid]:-}"
            ;;
    esac

    if [[ -z "$translation" ]]; then
        translation="$msgid"
    fi

    printf '%s' "$translation"
}

# 语言选择
select_language() {
    if [[ "$QUIET_MODE" == "true" ]]; then
        return
    fi

    # 如果已通过命令行或环境变量指定语言，直接使用
    if [[ -n "$CUDA_INSTALLER_LANG" ]]; then
        LANG_CURRENT="$CUDA_INSTALLER_LANG"
        return
    fi

    # 检测系统语言
    local sys_lang="${LANG:-en_US}"
    if [[ "$sys_lang" =~ ^zh ]]; then
        LANG_CURRENT="zh_CN"
    else
        LANG_CURRENT="en_US"
    fi
}

# 统一日志函数
__log() {
    local level="$1"; shift
    if [[ "$QUIET_MODE" == "true" ]] && [[ "$level" != "ERROR" ]] && [[ "$level" != "SUCCESS" ]]; then return; fi
    if [[ "$level" == "DEBUG" ]] && [[ "${VERBOSE:-0}" -eq 0 ]]; then return; fi
    local color
    case "$level" in
        INFO) color="$BLUE";; SUCCESS) color="$GREEN";; WARN) color="$YELLOW";;
        ERROR) color="$RED";; STEP) color="$PURPLE";; DEBUG) color="$BLUE";; *) color="";;
    esac
    local target=1; [[ "$level" == "ERROR" ]] && target=2
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] [${color}${level}${NC}] $*" >&$target
}

panic() { __log "ERROR" "$*"; exit 1; }
warn()  { __log "WARN" "$*"; }
info()  { __log "INFO" "$*"; }
debug() { __log "DEBUG" "$*"; }

# 信号处理
cleanup_on_exit() {
    local exit_code=$?
    local signal="${1:-EXIT}"

    debug "$(gettext "signal.cleaning_temp")"

    if [[ "$signal" != "EXIT" ]]; then
        warn "$(gettext "signal.interrupted") $signal"
        if [[ -d "$STATE_DIR" ]]; then
            echo "INTERRUPTED=true" >> "$STATE_DIR/last_exit_code"
            echo "SIGNAL=$signal" >> "$STATE_DIR/last_exit_code"
            echo "INTERRUPT_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$STATE_DIR/last_exit_code"
        fi
    fi

    cleanup_temp_files
    cleanup_lock_files

    if [[ "$signal" != "EXIT" ]] && [[ -f "$STATE_FILE" ]]; then
        info "$(gettext "signal.state_saved")"
    fi

    case "$signal" in
        "INT")  exit 130 ;;  # 128 + SIGINT(2)
        "TERM") exit 143 ;;  # 128 + SIGTERM(15)
        "EXIT")       exit $exit_code ;;
        *)            exit 1 ;;
    esac
}

cleanup_temp_files() {
    find /tmp -maxdepth 1 \( \
        -name "cuda-repo-*" -o \
        -name "cuda-keyring*.deb" \
    \) -print -exec rm -rf {} + 2>/dev/null || true
    find "${TMPDIR:-/tmp}" -maxdepth 1 -type d \
        -name "cuda-repo-*" -print -exec rm -rf {} + 2>/dev/null || true
}

cleanup_lock_files() {
    local lock_files=(
        "/tmp/.cuda-installer.lock"
        "$STATE_DIR/.install.lock"
    )
    for lock_file in "${lock_files[@]}"; do
        if [[ -f "$lock_file" ]]; then
            debug "$(gettext "signal.release_lock") $lock_file"
            rm -f "$lock_file"
        fi
    done
}

trap 'cleanup_on_exit INT' INT
trap 'cleanup_on_exit TERM' TERM
trap 'cleanup_on_exit EXIT' EXIT

# 退出码处理
exit_with_code() {
    local exit_code=$1
    local message="$2"

    __log "ERROR" "$message"

    if [[ -d "$STATE_DIR" ]]; then
        echo "EXIT_CODE=$exit_code" > "$STATE_DIR/last_exit_code"
        echo "EXIT_MESSAGE=$message" >> "$STATE_DIR/last_exit_code"
        echo "EXIT_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$STATE_DIR/last_exit_code"
    fi

    exit "$exit_code"
}

get_exit_code_description() {
    local code=$1
    case $code in
        0)   echo "$(gettext "exit_code.success")" ;;
        1)   echo "$(gettext "exit_code.no_root")" ;;
        3)   echo "$(gettext "exit_code.state_dir_failed")" ;;
        20)  echo "$(gettext "exit_code.unsupported_os")" ;;
        22)  echo "$(gettext "exit_code.unsupported_arch")" ;;
        30)  echo "$(gettext "exit_code.invalid_args")" ;;
        31)  echo "$(gettext "exit_code.invalid_install_type")" ;;
        60)  echo "$(gettext "exit_code.network_failed")" ;;
        71)  echo "$(gettext "exit_code.repo_add_failed")" ;;
        74)  echo "$(gettext "exit_code.pkg_install_failed")" ;;
        90)  echo "$(gettext "exit_code.rollback_file_missing")" ;;
        91)  echo "$(gettext "exit_code.rollback_failed")" ;;
        92)  echo "$(gettext "exit_code.state_file_corrupted")" ;;
        100) echo "$(gettext "exit_code.user_cancelled")" ;;
        *)   echo "$(gettext "exit_code.unknown_code") $code" ;;
    esac
}

show_exit_codes() {
    echo "CUDA Toolkit Installer - Exit Codes"
    echo "═══════════════════════════════════════════════════════════════"

    local -a codes=(0 1 3 20 22 30 31 60 71 74 90 91 92 100)
    for code in "${codes[@]}"; do
        printf "  %-4s - %s\n" "$code" "$(get_exit_code_description "$code")"
    done

    echo "═══════════════════════════════════════════════════════════════"
    echo "Last exit code: $STATE_DIR/last_exit_code"
}

# 交互式确认
confirm() {
    local prompt="$1"
    local default="${2:-N}"

    if [[ "$AUTO_YES" == "true" ]]; then
        info "$(gettext "prompt.confirm.auto_yes")"
        return 0
    fi

    if [[ "$QUIET_MODE" == "true" ]]; then
        return 0
    fi

    local answer
    echo -n -e "$prompt $(gettext "prompt.confirm.yes_or_no") "
    read -r answer
    # 空输入时采用默认值
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    case "${answer,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# 状态管理
create_state_dir() {
    if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
        exit_with_code $EXIT_STATE_DIR_FAILED "$(gettext "state.dir.create_failed") $STATE_DIR"
    fi
    chmod 755 "$STATE_DIR"
    create_install_lock
}

create_install_lock() {
    local lock_file="$STATE_DIR/.install.lock"

    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            exit_with_code $EXIT_STATE_FILE_CORRUPTED "$(gettext "state.lock.another_running") ($lock_pid)"
        else
            warn "$(gettext "state.lock.cleaning_orphaned")"
            rm -f "$lock_file"
        fi
    fi

    echo $$ > "$lock_file"
    debug "$(gettext "state.lock.created") $lock_file (PID: $$)"
}

save_state() {
    local step="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $step" >> "$STATE_FILE"
}

get_last_state() {
    if [[ -f "$STATE_FILE" ]]; then
        tail -1 "$STATE_FILE" | cut -d: -f2- | sed 's/^ *//'
    fi
}

is_step_completed() {
    local step="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep -q ": $step$" "$STATE_FILE"
    else
        return 1
    fi
}

save_rollback_info() {
    local action="$1"
    echo "$action" >> "$ROLLBACK_FILE"
}

cleanup_failed_install() {
    info "$(gettext "cleanup.starting")"

    if [[ -f "$STATE_FILE" ]]; then
        info "$(gettext "cleanup.state_found")"
        if [[ "$QUIET_MODE" != "true" ]]; then
            cat "$STATE_FILE"
        fi
        if confirm "$(gettext "cleanup.confirm")" "N"; then
            rm -f "$STATE_FILE" "$ROLLBACK_FILE"
            info "$(gettext "cleanup.done")"
        fi
    else
        info "$(gettext "cleanup.no_state")"
    fi
}

rollback_installation() {
    info "$(gettext "rollback.starting")"

    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        exit_with_code $EXIT_ROLLBACK_FILE_MISSING "$(gettext "rollback.file_missing") $ROLLBACK_FILE"
    fi

    warn "$(gettext "rollback.warning")"
    if [[ "$QUIET_MODE" != "true" ]]; then
        cat "$ROLLBACK_FILE"
    fi

    if confirm "$(gettext "rollback.confirm")" "N"; then
        local rollback_failed=false
        while read -r action; do
            info "$(gettext "rollback.executing") $action"
            if ! eval "$action"; then
                warn "$(gettext "rollback.partial_failure") $action"
                rollback_failed=true
            fi
        done < <(tac "$ROLLBACK_FILE")

        if [[ "$rollback_failed" == "true" ]]; then
            exit_with_code $EXIT_ROLLBACK_FAILED "$(gettext "rollback.partial_failure")"
        fi

        rm -f "$STATE_FILE" "$ROLLBACK_FILE"
        info "$(gettext "rollback.success")"
    else
        exit_with_code $EXIT_USER_CANCELLED "$(gettext "rollback.user_cancelled")"
    fi
}

# GPU 检测 (仅警告，不阻止安装)
check_nvidia_gpu() {
    info "$(gettext "gpu.check.starting")"

    if ! command -v lspci &>/dev/null; then
        warn "$(gettext "gpu.check.lspci_missing")"
        return 0
    fi

    if lspci | grep -qi nvidia; then
        info "$(gettext "gpu.check.found")"
    else
        warn "$(gettext "gpu.check.not_found")"
    fi
}

# ========== 业务逻辑 ==========

map_distro_id() {
    : "${ID:?}"

    case "$ID" in
    "debian") echo "debian" ;;
    "ubuntu") echo "ubuntu" ;;
    "rhel") echo "rhel" ;;
    "rocky") echo "rocky" ;;
    "ol") echo "ol" ;;
    "fedora") echo "fedora" ;;
    "sles") echo "sles" ;;
    "opensuse-leap") echo "opensuse" ;;
    *) exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): $ID" ;;
    esac
}

map_distro_version() {
    : "${VERSION_ID:?}"

    local distro_id
    distro_id="$(map_distro_id)"

    case "$distro_id" in
    "debian")
        case "$VERSION_ID" in
        "10") echo "10" ;;
        "11") echo "11" ;;
        "12") echo "12" ;;
        *) exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): Debian $VERSION_ID" ;;
        esac
        ;;
    "ubuntu")
        case "$VERSION_ID" in
        "12.04") echo "1204" ;; "12.10") echo "1210" ;; "13.04") echo "1304" ;;
        "14.04") echo "1404" ;; "14.10") echo "1410" ;; "15.04") echo "1504" ;;
        "16.04") echo "1604" ;; "17.04") echo "1704" ;; "17.10") echo "1710" ;;
        "18.04") echo "1804" ;; "18.10") echo "1810" ;; "20.04") echo "2004" ;;
        "22.04") echo "2204" ;; "24.04") echo "2404" ;;
        *) exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): Ubuntu $VERSION_ID" ;;
        esac
        ;;
    "rhel" | "rocky" | "ol")
        case "$VERSION_ID" in
        "6") echo "6" ;; "7") echo "7" ;; "8") echo "8" ;; "9") echo "9" ;; "10") echo "10" ;;
        *) exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): RHEL/Rocky/OL $VERSION_ID" ;;
        esac
        ;;
    "fedora")
        case "$VERSION_ID" in
        "18") echo "18" ;; "19") echo "19" ;; "20") echo "20" ;;
        "21" | "22") echo "21" ;; "23" | "24") echo "23" ;; "25" | "26") echo "25" ;;
        "27" | "28") echo "27" ;; "29" | "30" | "31") echo "29" ;;
        "32") echo "32" ;; "33") echo "33" ;; "34") echo "34" ;; "35") echo "35" ;;
        "36") echo "36" ;; "37" | "38") echo "37" ;; "39") echo "39" ;; "40") echo "40" ;;
        "41" | "42") echo "41" ;;
        *) exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): Fedora $VERSION_ID" ;;
        esac
        ;;
    "sles" | "opensuse")
        case "$VERSION_ID" in
        "15"*) echo "15" ;;
        *) exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): SLES/OpenSUSE $VERSION_ID" ;;
        esac
        ;;
    *)
        exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): $distro_id"
        ;;
    esac
}

map_arch() {
    local __arch
    __arch="$(arch)"

    case "$__arch" in
    "x86_64") echo "x86_64" ;;
    "arm64" | "aarch64") echo "arm64" ;;
    *) exit_with_code $EXIT_UNSUPPORTED_ARCH "$(gettext "exit_code.unsupported_arch"): $__arch" ;;
    esac
}

detect_package_manager() {
    info "$(gettext "log.detect_pm")"

    case "$distro_id" in
    debian | ubuntu)
        if command -v apt &>/dev/null; then
            echo "apt"
        else
            exit_with_code $EXIT_UNSUPPORTED_OS "apt not found."
        fi
        ;;
    rhel | fedora | rocky | ol)
        if command -v dnf &>/dev/null; then
            echo "dnf"
        elif command -v yum &>/dev/null; then
            echo "yum"
        else
            exit_with_code $EXIT_UNSUPPORTED_OS "Neither dnf nor yum found."
        fi
        ;;
    opensuse | sles)
        if command -v zypper &>/dev/null; then
            echo "zypper"
        else
            exit_with_code $EXIT_UNSUPPORTED_OS "zypper not found."
        fi
        ;;
    *)
        exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "exit_code.unsupported_os"): $distro_id"
        ;;
    esac
}

# shellcheck disable=SC2329
__pm_inst_apt__() {
    $DRY_RUN apt-get update
    $DRY_RUN apt-get install -y --no-install-recommends "${@}"
}

# shellcheck disable=SC2329
__pm_inst_dnf__() {
    $DRY_RUN dnf install -y --setopt=install_weak_deps=False "${@}"
}

# shellcheck disable=SC2329
__pm_inst_yum__() {
    $DRY_RUN yum clean all
    $DRY_RUN yum install -y --setopt=install_weak_deps=False "${@}"
}

# shellcheck disable=SC2329
__pm_inst_zypper__() {
    $DRY_RUN zypper refresh
    $DRY_RUN zypper install -y "${@}"
}

pm_inst() {
    info "$(gettext "log.install_pkg") ${*}"
    local fn="__pm_inst_${pm}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn" "${@}"
    else
        exit_with_code $EXIT_PKG_INSTALL_FAILED "Unsupported package manager: $pm"
    fi
}

# shellcheck disable=SC2329
__pm_query_apt__() {
    apt-cache search -qn "${@}" | sed -E 's/^(\S+) .*$/\1/gm;t'
}

# shellcheck disable=SC2329
__pm_query_dnf__() {
    dnf list --available | sed -E 's/^(\S+) .*$/\1/gm;t' | grep -E "${@}"
}

# shellcheck disable=SC2329
__pm_query_yum__() {
    yum list --available "${@}" | sed -E 's/^(\S+) .*$/\1/gm;t' | grep -E "${@}"
}

# shellcheck disable=SC2329
__pm_query_zypper__() {
    zypper search --match-exact "${@}" | sed -E 's/^(\S+) .*$/\1/gm;t' | grep -E "${@}"
}

pm_query() {
    info "$(gettext "log.query_pkg") ${*}"
    local fn="__pm_query_${pm}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn" "${@}"
    else
        exit_with_code $EXIT_UNSUPPORTED_OS "Unsupported package manager: $pm"
    fi
}

# shellcheck disable=SC2329
__preinstall_rhel_8__() {
    info "Enabling RHEL 8 repositories for CUDA installation"
    $DRY_RUN subscription-manager repos --enable=rhel-8-for-"$arch"-appstream-rpms
    $DRY_RUN subscription-manager repos --enable=rhel-8-for-"$arch"-baseos-rpms
    $DRY_RUN subscription-manager repos --enable=codeready-builder-for-rhel-8-"$arch"-rpms
}

# shellcheck disable=SC2329
__preinstall_rhel_9__() {
    info "Enabling RHEL 9 repositories for CUDA installation"
    $DRY_RUN subscription-manager repos --enable=rhel-9-for-"$arch"-appstream-rpms
    $DRY_RUN subscription-manager repos --enable=rhel-9-for-"$arch"-baseos-rpms
    $DRY_RUN subscription-manager repos --enable=codeready-builder-for-rhel-9-"$arch"-rpms
}

# shellcheck disable=SC2329
__preinstall_rhel__() {
    local fn="__preinstall_rhel_${distro_version}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn"
    else
        info "No pre-installation steps required for RHEL ${distro_version}"
    fi
}

# shellcheck disable=SC2329
__preinstall_rocky_8__() {
    info "Enabling Rocky Linux 8 repositories for CUDA installation"
    $DRY_RUN dnf config-manager --set-enabled powertools
}

# shellcheck disable=SC2329
__preinstall_rocky_9__() {
    info "Enabling Rocky Linux 9 repositories for CUDA installation"
    $DRY_RUN dnf config-manager --set-enabled crb
}

# shellcheck disable=SC2329
__preinstall_rocky__() {
    local fn="__preinstall_rocky_${distro_version}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn"
    else
        info "No pre-installation steps required for Rocky Linux ${distro_version}"
    fi
}

# shellcheck disable=SC2329
__preinstall_ol_8__() {
    info "Enabling Oracle Linux 8 repositories for CUDA installation"
    $DRY_RUN dnf config-manager --set-enabled ol8_codeready_builder
}

# shellcheck disable=SC2329
__preinstall_ol_9__() {
    info "Enabling Oracle Linux 9 repositories for CUDA installation"
    $DRY_RUN dnf config-manager --set-enabled ol9_codeready_builder
}

# shellcheck disable=SC2329
__preinstall_ol__() {
    local fn="__preinstall_ol_${distro_version}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn"
    else
        info "No pre-installation steps required for Oracle Linux ${distro_version}"
    fi
}

# shellcheck disable=SC2329
__preinstall_debian__() {
    $DRY_RUN add-apt-repository contrib
}

preinstall() {
    if is_step_completed "preinstall"; then
        debug "$(gettext "state.step.already_done") preinstall"
        return 0
    fi

    info "$(gettext "log.preinstall")"

    local fn="__preinstall_${distro_id}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn"
    else
        info "$(gettext "log.preinstall.none")"
    fi

    save_state "preinstall"
}

# shellcheck disable=SC2329
__addrepo_debian__() {
    local temp_dir
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/cuda-repo-XXXXXX")

    $DRY_RUN wget "${repo_url}/cuda-keyring_1.1-1_all.deb" -O "$temp_dir/cuda-keyring_1.1-1_all.deb"
    $DRY_RUN env DEBIAN_FRONTEND=noninteractive dpkg -i "$temp_dir/cuda-keyring_1.1-1_all.deb"
    save_rollback_info "dpkg -r cuda-keyring"
    $DRY_RUN rm -rf "$temp_dir"
    $DRY_RUN apt-get update
}

# shellcheck disable=SC2329
__addrepo_ubuntu__() {
    __addrepo_debian__
}

# shellcheck disable=SC2329
__addrepo_fedora__() {
    $DRY_RUN dnf config-manager --add-repo "${repo_url}/cuda-${distro}.repo"
    save_rollback_info "rm -f /etc/yum.repos.d/cuda-${distro}.repo"
}

# shellcheck disable=SC2329
__addrepo_rhel__() {
    __addrepo_fedora__
}

# shellcheck disable=SC2329
__addrepo_rocky__() {
    __addrepo_fedora__
}

# shellcheck disable=SC2329
__addrepo_sles__() {
    $DRY_RUN zypper addrepo "$repo_url/cuda-$distro.repo"
    save_rollback_info "zypper removerepo cuda-$distro"
}

# shellcheck disable=SC2329
__addrepo_ol__() {
    __addrepo_fedora__
}

# shellcheck disable=SC2329
__addrepo_opensuse__() {
    __addrepo_sles__
}

addrepo() {
    if is_step_completed "addrepo"; then
        debug "$(gettext "state.step.already_done") addrepo"
        return 0
    fi

    info "$(gettext "log.addrepo")"

    local fn="__addrepo_${distro_id}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn"
    else
        info "$(gettext "log.addrepo.none")"
    fi

    save_state "addrepo"
}

select_cuda_version() {
    local -n __cuda_version_ref="$1"
    info "$(gettext "log.install_cuda.select")"
    local versions
    versions="$(pm_query "^cuda-[0-9]+-[0-9]+" | sed -E 's/^cuda-(.+)$/\1/' | sort -u)"
    debug "pm_query returned: $versions"

    if [[ -z "$versions" ]]; then
        exit_with_code $EXIT_PKG_INSTALL_FAILED "$(gettext "select.cuda_version.no_versions")"
    fi

    # shellcheck disable=SC2206
    version_array=( $versions )
    for v in "${version_array[@]}"; do
        debug "Found available CUDA version: $v"
    done

    echo "=================================================="
    echo "$(gettext "select.cuda_version.header")"
    select version in "${version_array[@]}"; do
        if [[ -n "$version" ]]; then
            __cuda_version_ref="$version"
            break
        fi
    done
}

install_cuda() {
    if is_step_completed "install_cuda"; then
        debug "$(gettext "state.step.already_done") install_cuda"
        return 0
    fi

    if [[ "$INSTALL_TYPE" == "cuda" || "$INSTALL_TYPE" == "all" ]]; then
        info "$(gettext "log.install_cuda")"
        if [[ "$CUDA_VERSION" == "auto" ]]; then
            info "$(gettext "log.install_cuda.auto")"
            pm_inst cuda
        elif [[ -n "$CUDA_VERSION" ]]; then
            info "$(gettext "log.install_cuda.version") $CUDA_VERSION"
            pm_inst "cuda-$CUDA_VERSION"
        else
            local __ver
            select_cuda_version __ver
            pm_inst "cuda-$__ver"
        fi
        save_state "install_cuda"
    else
        info "$(gettext "log.install_cuda.skip")"
    fi
}

install_ctk() {
    if is_step_completed "install_ctk"; then
        debug "$(gettext "state.step.already_done") install_ctk"
        return 0
    fi

    if [[ "$INSTALL_TYPE" == "ctk" || "$INSTALL_TYPE" == "all" ]]; then
        info "$(gettext "log.install_ctk")"
        pm_inst nvidia-container-toolkit
        save_state "install_ctk"
    else
        info "$(gettext "log.install_ctk.skip")"
    fi
}

main() {
    info "$(gettext "log.starting")"

    # 检查 root 权限
    debug "$(gettext "log.root_check")"
    if [ "$EUID" -ne 0 ]; then
        exit_with_code $EXIT_NO_ROOT "$(gettext "log.root_check.fail")"
    fi

    # 创建状态目录和锁
    create_state_dir

    # 检测操作系统
    info "$(gettext "log.detect_os")"
    if [ -f "/etc/os-release" ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    elif [ -f "/usr/lib/os-release" ]; then
        # shellcheck disable=SC1091
        . /usr/lib/os-release
    else
        exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "log.detect_os.fail")"
    fi

    local distro_id
    distro_id="$(map_distro_id)"

    local distro_version
    distro_version="$(map_distro_version)"

    local distro
    distro="${distro_id}${distro_version}"
    info "$(gettext "log.detect_os.success") $distro"

    local arch
    arch="$(map_arch)"
    info "$(gettext "log.detect_arch") $arch"

    local repo_url="${NVIDIA_REPO_BASE_URL}/${distro}/${arch}"
    info "$(gettext "log.repo_url") $repo_url"

    local pm=
    pm="$(detect_package_manager)"
    info "$(gettext "log.detect_pm.result") $pm"

    # GPU 检测 (仅警告)
    if [[ "$SKIP_GPU_CHECK" != "true" ]]; then
        check_nvidia_gpu
    fi

    # 显示安装配置摘要 + 确认
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo
        echo -e "${GREEN}$(gettext "confirm.install.header")${NC}"
        echo -e "  $(gettext "confirm.install.distro"): $distro"
        echo -e "  $(gettext "confirm.install.arch"): $arch"
        echo -e "  $(gettext "confirm.install.type"): $INSTALL_TYPE"
        echo -e "  $(gettext "confirm.install.cuda_version"): ${CUDA_VERSION:-auto}"
        echo -e "  $(gettext "confirm.install.repo_url"): $repo_url"
        echo

        if ! confirm "$(gettext "confirm.install.proceed")"; then
            exit_with_code $EXIT_USER_CANCELLED "$(gettext "exit_code.user_cancelled")"
        fi
    fi

    # 安装步骤 (状态保护)
    preinstall
    addrepo
    install_cuda
    install_ctk

    save_state "installation_completed"
    echo
    __log "SUCCESS" "$(gettext "final.success")"
    exit 0
}

help() {
    cat <<EOF
CUDA Toolkit One-Click Installer v${SCRIPT_VERSION}

Usage: $(basename "$0") [OPTIONS]

Currently supported distros:
    Debian, Ubuntu, Fedora, RHEL, Rocky Linux, Oracle Linux, SLES, OpenSUSE

Options:
    -h, --help              Show this help message and exit
    -v, --verbose           Enable verbose output
    -q, --quiet             Enable quiet output
    -n, --dry-run           Enable dry run mode (most changes won't be made)
    -y, --yes               Auto-confirm all prompts (non-interactive mode)
    --lang LANG             Set interface language: zh_CN, en_US (default: zh_CN)
    --type=<type>           Specify installation type: 'cuda', 'ctk', 'all', 'none' [Default: 'cuda']
                            'cuda'  Install CUDA Toolkit only
                            'ctk'   Install NVIDIA Container Toolkit only
                            'all'   Install both CUDA and Container Toolkits
                            'none'  Do not install anything (configure repository only)
    --cuda-version=<version> Specify CUDA version to install
                            <version>  Specific version (e.g. '12-9')
                            'auto'     Automatically install the latest version
                            leave empty to select interactively
    --use-cn-cdn            Use CN CDN for NVIDIA repository
    --skip-gpu-check        Skip NVIDIA GPU detection
    --cleanup               Clean up failed installation state
    --rollback              Rollback to pre-installation state
    --show-exit-codes       Show all exit codes and descriptions

Environment Variables:
    NVIDIA_REPO_BASE_URL        Base URL for the NVIDIA repository
                                [Default: "https://developer.download.nvidia.com/compute/cuda/repos"]
    TMPDIR                      Temporary directory for downloaded files
    CUDA_INSTALLER_AUTO_YES     Equivalent to -y
    CUDA_INSTALLER_QUIET        Equivalent to -q
    CUDA_INSTALLER_LANG         Set interface language (zh_CN, en_US)

EOF
    exit 0
}

__main() {
    local VERBOSE=0
    local NVIDIA_REPO_BASE_URL="${NVIDIA_REPO_BASE_URL:-"https://developer.download.nvidia.com/compute/cuda/repos"}"
    local INSTALL_TYPE="cuda"
    local DRY_RUN=
    local CUDA_VERSION=
    local SKIP_GPU_CHECK=false

    # 预解析: 提取 --quiet, --yes, --lang (在语言选择前)
    for arg in "$@"; do
        case "$arg" in
            -q|--quiet)   QUIET_MODE=true ;;
            -y|--yes)     AUTO_YES=true ;;
        esac
    done

    # 环境变量支持
    if [[ "$CUDA_INSTALLER_AUTO_YES" == "true" ]]; then AUTO_YES=true; fi
    if [[ "$CUDA_INSTALLER_QUIET" == "true" ]]; then QUIET_MODE=true; fi

    # 语言选择
    select_language

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            help
            ;;
        -v | --verbose)
            VERBOSE=1
            debug "Verbose mode enabled"
            ;;
        -q | --quiet)
            QUIET_MODE=true
            ;;
        -n | --dry-run)
            debug "Dry run mode enabled"
            DRY_RUN="echo"
            ;;
        -y | --yes)
            AUTO_YES=true
            ;;
        --lang)
            if [[ -z "${2:-}" ]]; then
                exit_with_code $EXIT_INVALID_ARGS "$(gettext "args.error.missing_value"): --lang"
            fi
            LANG_CURRENT="${2:-}"
            shift
            ;;
        --type=*)
            INSTALL_TYPE="${1#*=}"
            if ! [[ "${INSTALL_TYPE}" =~ ^(cuda|ctk|all|none)$ ]]; then
                exit_with_code $EXIT_INVALID_INSTALL_TYPE "$(gettext "exit_code.invalid_install_type"): $INSTALL_TYPE"
            fi
            debug "Install type set to: $INSTALL_TYPE"
            ;;
        --cuda-version=*)
            CUDA_VERSION="${1#*=}"
            debug "CUDA version set to: $CUDA_VERSION"
            ;;
        --use-cn-cdn)
            NVIDIA_REPO_BASE_URL="https://developer.download.nvidia.cn/compute/cuda/repos"
            debug "Using CN CDN for NVIDIA repository"
            ;;
        --skip-gpu-check)
            SKIP_GPU_CHECK=true
            ;;
        --cleanup)
            create_state_dir
            cleanup_failed_install
            exit 0
            ;;
        --rollback)
            create_state_dir
            rollback_installation
            exit 0
            ;;
        --show-exit-codes)
            show_exit_codes
            exit 0
            ;;
        *)
            exit_with_code $EXIT_INVALID_ARGS "$(gettext "exit_code.invalid_args"): $1"
            ;;
        esac
        shift
    done

    main
}

__main "${@}"
