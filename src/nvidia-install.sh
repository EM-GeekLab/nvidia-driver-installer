#!/bin/bash

# NVIDIA 驱动一键安装脚本
# NVIDIA Driver One-Click Installer

# Author: PEScn @ EM-GeekLab
# Modified: 2026-02-17
# License: Apache-2.0
# GitHub: https://github.com/EM-GeekLab/nvidia-driver-installer
# Base on NVIDIA Driver Installation Guide: https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/index.html
# Supports Ubuntu, CentOS, SUSE, RHEL, Fedora, Amazon Linux, Azure Linux and other distributions.
# This script need `root` privileges to run, or use `sudo` to run it.

# ==============================================================================
# Usage | 用法
# ==============================================================================
# 1. download the script | 下载脚本
#
#   $ curl -sSL https://raw.githubusercontent.com/EM-GeekLab/nvidia-driver-installer/main/nvidia-install.sh -o nvidia-install.sh
#
# 2. [Optional] verify the script's content | 【可选】验证脚本内容
#
#   $ cat nvidia-install.sh
#
# 3. run the script either as root, or using sudo to perform the installation. | 以 root 权限或使用 sudo 运行脚本进行安装
#
#   $ sudo bash nvidia-install.sh
#
# ==============================================================================

set -eo pipefail

readonly SCRIPT_VERSION="2.2"

# Color Definitions for echo output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Exit code definitions for automation
readonly EXIT_SUCCESS=0

# 权限和环境错误 (1-9)
readonly EXIT_NO_ROOT=1
readonly EXIT_PERMISSION_DENIED=2
readonly EXIT_STATE_DIR_FAILED=3

# 硬件检测错误 (10-19) 
readonly EXIT_NO_NVIDIA_GPU=10
readonly EXIT_LSPCI_UNAVAILABLE=11
readonly EXIT_GPU_ARCH_INCOMPATIBLE=12

# 系统兼容性错误 (20-29)
readonly EXIT_UNSUPPORTED_OS=20
readonly EXIT_UNSUPPORTED_VERSION=21
readonly EXIT_UNSUPPORTED_ARCH=22

# 参数和配置错误 (30-39)
readonly EXIT_INVALID_ARGS=30
readonly EXIT_INVALID_INSTALL_TYPE=31
readonly EXIT_MODULE_ARCH_MISMATCH=32

# Secure Boot相关错误 (40-49)
readonly EXIT_SECURE_BOOT_USER_EXIT=40
readonly EXIT_SECURE_BOOT_AUTO_FAILED=41
readonly EXIT_MOK_OPERATION_FAILED=42
readonly EXIT_MOK_TOOLS_MISSING=43

# 现有驱动冲突 (50-59)
readonly EXIT_EXISTING_DRIVER_USER_EXIT=50
readonly EXIT_DRIVER_UNINSTALL_FAILED=51
readonly EXIT_NOUVEAU_DISABLE_FAILED=52

# 网络和下载错误 (60-69)
readonly EXIT_NETWORK_FAILED=60
readonly EXIT_REPO_DOWNLOAD_FAILED=61
readonly EXIT_KEYRING_DOWNLOAD_FAILED=62

# 包管理器错误 (70-79)
readonly EXIT_PACKAGE_MANAGER_UNAVAILABLE=70
readonly EXIT_REPO_ADD_FAILED=71
readonly EXIT_DEPENDENCY_INSTALL_FAILED=72
readonly EXIT_KERNEL_HEADERS_FAILED=73
readonly EXIT_NVIDIA_INSTALL_FAILED=74

# 系统状态错误 (80-89)
readonly EXIT_KERNEL_VERSION_ISSUE=80
readonly EXIT_DKMS_BUILD_FAILED=81
readonly EXIT_MODULE_SIGNING_FAILED=82
readonly EXIT_DRIVER_VERIFICATION_FAILED=83

# 状态管理错误 (90-99)
readonly EXIT_ROLLBACK_FILE_MISSING=90
readonly EXIT_ROLLBACK_FAILED=91
readonly EXIT_STATE_FILE_CORRUPTED=92

# 用户取消 (100-109)
readonly EXIT_USER_CANCELLED=100

# 全局变量
DISTRO_ID=""
DISTRO_VERSION=""
DISTRO_CODENAME=""
ARCH=""
PKG_FAMILY=""
USE_OPEN_MODULES=true
INSTALL_TYPE="full"  # full, compute-only, desktop-only
USE_LOCAL_REPO=false
FORCE_REINSTALL=false
SKIP_EXISTING_CHECKS=false
AUTO_YES=false
QUIET_MODE=false
REBOOT_AFTER_INSTALL=false
DRIVER_VERSION=""

# 状态跟踪文件
STATE_DIR="/var/lib/nvidia-installer"
STATE_FILE="$STATE_DIR/install.state"
ROLLBACK_FILE="$STATE_DIR/rollback.list"

# 环境变量配置支持
NVIDIA_INSTALLER_AUTO_YES=${NVIDIA_INSTALLER_AUTO_YES:-false}
NVIDIA_INSTALLER_QUIET=${NVIDIA_INSTALLER_QUIET:-false}
NVIDIA_INSTALLER_MODULES=${NVIDIA_INSTALLER_MODULES:-"open"}
NVIDIA_INSTALLER_TYPE=${NVIDIA_INSTALLER_TYPE:-"full"}
NVIDIA_INSTALLER_FORCE=${NVIDIA_INSTALLER_FORCE:-false}
NVIDIA_INSTALLER_REBOOT=${NVIDIA_INSTALLER_REBOOT:-false}
LANG_CURRENT="${NVIDIA_INSTALLER_LANG:-zh_CN}"  # 默认语言为中文

# ================ Language Packs ==================
# {{LANG_PACKS}}
# ================ Language Packs End ==============


gettext() {
    local msgid="$1"
    local translation=""
    
    # 根据当前语言获取翻译
    case "$LANG_CURRENT" in
        "zh-cn"|"zh"|"zh_CN")
            translation="${LANG_PACK_ZH_CN[$msgid]:-}"
            ;;
        "en-us"|"en"|"en_US")
            translation="${LANG_PACK_EN_US[$msgid]:-}"
            ;;
        *)
            # 默认使用中文
            translation="${LANG_PACK_ZH_CN[$msgid]:-}"
            ;;
    esac
    
    # 如果没有找到翻译，返回key本身
    if [[ -z "$translation" ]]; then
        translation="$msgid"
    fi
    
    printf '%s' "$translation"  # 使用 printf 而不是 echo
}

# 优雅退出处理
cleanup_on_exit() {
    local exit_code=$?
    local signal="${1:-EXIT}"

    log_debug "$(gettext "exit.handler.receive_signal") $signal, $(gettext "exit.handler.exit_code") $exit_code"

    # 如果是被信号中断，记录中断信息
    if [[ "$signal" != "EXIT" ]]; then
        log_warning "$(gettext "exit.handler.script_interrupted") $signal"

        # 保存中断状态
        if [[ -d "$STATE_DIR" ]]; then
            echo "INTERRUPTED=true" >> "$STATE_DIR/last_exit_code"
            echo "SIGNAL=$signal" >> "$STATE_DIR/last_exit_code"
            echo "INTERRUPT_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$STATE_DIR/last_exit_code"
        fi
    fi
    
    # 清理临时文件
    cleanup_temp_files
    
    # 如果安装过程中被中断，保存当前状态
    if [[ "$signal" != "EXIT" ]] && [[ -f "$STATE_FILE" ]]; then
        log_info "$(gettext "exit.handler.state_saved_for_resume")"
    fi
    
    # 释放可能的锁文件
    cleanup_lock_files
    
    # 根据信号设置适当的退出码
    case "$signal" in
        "INT")
            exit 130  # 128 + SIGINT(2)
            ;;
        "TERM")
            exit 143  # 128 + SIGTERM(15)
            ;;
        "EXIT")
            exit $exit_code  # 保持原始退出码
            ;;
        *)
            exit 1
            ;;
    esac
}

# 清理临时文件
cleanup_temp_files() {
    log_debug "$(gettext "exit.handler.temp_files_starting")"
    find /tmp -maxdepth 1 \( \
        -name "nvidia-driver-local-repo-*.rpm" -o \
        -name "nvidia-driver-local-repo-*.deb" -o \
        -name "cuda-keyring*.deb" -o \
        -name "nvidia-installer-*.log" \
    \) -print -delete
}

# 清理锁文件
cleanup_lock_files() {
    local lock_files=(
        "/tmp/.nvidia-installer.lock"
        "/var/lock/nvidia-installer.lock"
        "$STATE_DIR/.install.lock"
    )
    
    for lock_file in "${lock_files[@]}"; do
        if [[ -f "$lock_file" ]]; then
            log_debug "$(gettext "clean.release_lock_file") $lock_file"
            rm -f "$lock_file"
        fi
    done
}

# 创建安装锁
create_install_lock() {
    local lock_file="$STATE_DIR/.install.lock"
    
    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            exit_with_code $EXIT_STATE_FILE_CORRUPTED "$(gettext "state.lock.error.another_install_running") $lock_pid"
        else
            log_warning "$(gettext "state.lock.cleaning_orphaned_file")"
            rm -f "$lock_file"
        fi
    fi
    
    echo $$ > "$lock_file"
    log_debug "$(gettext "state.lock.created") $lock_file (PID: $$)"
}

# 设置信号处理
trap 'cleanup_on_exit INT' INT
trap 'cleanup_on_exit TERM' TERM  
trap 'cleanup_on_exit EXIT' EXIT

# 错误处理函数
exit_with_code() {
    local exit_code=$1
    local message="$2"
    
    log_error "$message"
    
    # 在调试模式下显示退出码
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log_debug "$(gettext "exit.code.prompt") $exit_code"
    fi
    
    # 保存退出码到状态文件供外部查询
    if [[ -d "$STATE_DIR" ]]; then
        echo "EXIT_CODE=$exit_code" > "$STATE_DIR/last_exit_code"
        echo "EXIT_MESSAGE=$message" >> "$STATE_DIR/last_exit_code"
        echo "EXIT_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$STATE_DIR/last_exit_code"
    fi
    
    exit $exit_code
}

# 获取退出码描述
get_exit_code_description() {
    local code=$1
    case $code in
        0) echo "$(gettext "exit_code.success")" ;;
        1) echo "$(gettext "exit_code.permission.no_root")" ;;
        2) echo "$(gettext "exit_code.permission.fs_denied")" ;;
        3) echo "$(gettext "exit_code.permission.state_dir_failed")" ;;
        10) echo "$(gettext "exit_code.hardware.no_gpu_detected")" ;;
        11) echo "$(gettext "exit_code.hardware.lspci_unavailable")" ;;
        12) echo "$(gettext "exit_code.hardware.gpu_arch_incompatible")" ;;
        20) echo "$(gettext "exit_code.compatibility.unsupported_os")" ;;
        21) echo "$(gettext "exit_code.compatibility.unsupported_version")" ;;
        22) echo "$(gettext "exit_code.compatibility.unsupported_arch")" ;;
        30) echo "$(gettext "exit_code.config.invalid_args")" ;;
        31) echo "$(gettext "exit_code.config.invalid_install_type")" ;;
        32) echo "$(gettext "exit_code.config.module_arch_mismatch")" ;;
        40) echo "$(gettext "exit_code.secure_boot.user_exit")" ;;
        41) echo "$(gettext "exit_code.secure_boot.auto_failed")" ;;
        42) echo "$(gettext "exit_code.secure_boot.mok_operation_failed")" ;;
        43) echo "$(gettext "exit_code.secure_boot.mok_tools_missing")" ;;
        50) echo "$(gettext "exit_code.conflict.existing_driver_user_exit")" ;;
        51) echo "$(gettext "exit_code.conflict.driver_uninstall_failed")" ;;
        52) echo "$(gettext "exit_code.conflict.nouveau_disable_failed")" ;;
        60) echo "$(gettext "exit_code.network.connection_failed")" ;;
        61) echo "$(gettext "exit_code.network.repo_download_failed")" ;;
        62) echo "$(gettext "exit_code.network.keyring_download_failed")" ;;
        70) echo "$(gettext "exit_code.pkg_manager.unavailable")" ;;
        71) echo "$(gettext "exit_code.pkg_manager.repo_add_failed")" ;;
        72) echo "$(gettext "exit_code.pkg_manager.dependency_install_failed")" ;;
        73) echo "$(gettext "exit_code.pkg_manager.kernel_headers_failed")" ;;
        74) echo "$(gettext "exit_code.pkg_manager.nvidia_install_failed")" ;;
        80) echo "$(gettext "exit_code.system_state.kernel_version_issue")" ;;
        81) echo "$(gettext "exit_code.system_state.dkms_build_failed")" ;;
        82) echo "$(gettext "exit_code.system_state.module_signing_failed")" ;;
        83) echo "$(gettext "exit_code.system_state.driver_verification_failed")" ;;
        90) echo "$(gettext "exit_code.state_management.rollback_file_missing")" ;;
        91) echo "$(gettext "exit_code.state_management.rollback_failed")" ;;
        92) echo "$(gettext "exit_code.state_management.state_file_corrupted")" ;;
        100) echo "$(gettext "exit_code.user_cancelled")" ;;
        *) echo "$(gettext "exit_code.unknown_code") $code" ;;
    esac
}

# 统一日志函数
__log() {
    local level="$1"; shift
    if [[ "$QUIET_MODE" == "true" ]] && [[ "$level" != "ERROR" ]] && [[ "$level" != "SUCCESS" ]]; then return; fi
    if [[ "$level" == "DEBUG" ]] && [[ "${DEBUG:-false}" != "true" ]]; then return; fi
    local color
    case "$level" in
        INFO) color="$BLUE";; SUCCESS) color="$GREEN";; WARNING) color="$YELLOW";;
        ERROR) color="$RED";; STEP) color="$PURPLE";; DEBUG) color="$BLUE";; *) color="";;
    esac
    local target=1; [[ "$level" == "ERROR" ]] && target=2
    echo -e "${color}[${level}]${NC} $*" >&$target
}
log_info()    { __log INFO "$@"; }
log_success() { __log SUCCESS "$@"; }
log_warning() { __log WARNING "$@"; }
log_error()   { __log ERROR "$@"; }
log_step()    { __log STEP "$@"; }
log_debug()   { __log DEBUG "$@"; }

# 交互式确认函数
confirm() {
    local prompt="$1"
    local default="${2:-N}"

    if [[ "$AUTO_YES" == "true" ]]; then
        log_debug "$(gettext "auto_yes.prompt") $prompt -> Y"
        return 0
    fi
    
    if [[ "$default" == "Y" ]]; then
        read -p "$prompt (Y/n): " -r
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        read -p "$prompt (y/N): " -r
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# 选择菜单函数 (支持自动化)
select_option() {
    local prompt="$1"
    local default="$2"
    shift 2
    local options=("$@")

    if [[ "$AUTO_YES" == "true" ]]; then
        log_debug "$(gettext "auto_yes.prompt") $prompt -> $default"
        echo "$default"
        return 0
    fi
    
    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "$((i+1)). ${options[$i]}"
    done
    echo
    
    while true; do
        read -p "$(gettext "select_option.prompt.range") (1-${#options[@]}, $(gettext "select_option.prompt.default"): $default): " -r choice
        
        # 如果用户直接回车，使用默认值
        if [[ -z "$choice" ]]; then
            choice="$default"
        fi
        
        # 验证输入
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            echo "$choice"
            return 0
        else
            echo "$(gettext "select_option.prompt.invalid_choice") 1-${#options[@]}"
        fi
    done
}

# 显示用法
show_usage() {
    cat << EOF
用法: $0 [选项]

基本选项:
    -h, --help              显示此帮助信息
    -t, --type TYPE         安装类型: full, compute-only, desktop-only (默认: full)
    -m, --modules TYPE      内核模块类型: open, proprietary (默认: open)
    -l, --local             使用本地仓库安装
    -v, --version VERSION   指定驱动版本 (例如: 575)
    --lang LANG             设置界面语言: zh_CN, en_US (默认: zh_CN)

自动化选项:
    -y, --yes               自动确认所有提示 (无交互模式)
    -q, --quiet             静默模式，减少输出
    -f, --force             强制重新安装，即使已安装驱动
    -s, --skip-checks       跳过现有安装检查
    --auto-reboot           安装完成后自动重启

高级选项:
    --cleanup               清理失败的安装状态并退出
    --rollback              回滚到安装前状态
    --show-exit-codes       显示所有退出码及其含义

环境变量:
    NVIDIA_INSTALLER_AUTO_YES=true     等同于 -y
    NVIDIA_INSTALLER_QUIET=true        等同于 -q  
    NVIDIA_INSTALLER_MODULES=open      等同于 -m open
    NVIDIA_INSTALLER_TYPE=full         等同于 -t full
    NVIDIA_INSTALLER_FORCE=true        等同于 -f
    NVIDIA_INSTALLER_REBOOT=true       等同于 --auto-reboot
    NVIDIA_INSTALLER_LANG=zh_CN        设置界面语言 (zh_CN, en_US)

示例:
    # 交互式安装
    $0
    
    # 完全自动化安装
    $0 -y -q --auto-reboot
    
    # 无交互计算专用安装
    $0 -y -t compute-only -m proprietary
    
    # 环境变量方式
    NVIDIA_INSTALLER_AUTO_YES=true NVIDIA_INSTALLER_TYPE=compute-only $0
    
    # CI/CD环境使用
    $0 -y -q -f -t full --auto-reboot

注意: 
- 开源模块仅支持 Turing 及更新架构 GPU
- Maxwell、Pascal、Volta 架构必须使用专有模块
- 脚本支持幂等操作，可安全重复运行
- 自动化模式下会使用合理的默认值
EOF
}

# 显示退出码信息
show_exit_codes() {
    cat << 'EOF'
NVIDIA驱动安装脚本 - 退出码说明
═══════════════════════════════════════════════════════════════
EOF

    # GETTEXT_DYNAMIC: exit_code.permission exit_code.hardware exit_code.compatibility exit_code.config exit_code.secure_boot exit_code.conflict exit_code.network exit_code.pkg_manager exit_code.system_state exit_code.state_management
    local -a categories=(
        "exit_code.permission|1 2 3"
        "exit_code.hardware|10 11 12"
        "exit_code.compatibility|20 21 22"
        "exit_code.config|30 31 32"
        "exit_code.secure_boot|40 41 42 43"
        "exit_code.conflict|50 51 52"
        "exit_code.network|60 61 62"
        "exit_code.pkg_manager|70 71 72 73 74"
        "exit_code.system_state|80 81 82 83"
        "exit_code.state_management|90 91 92"
        "exit_code.user_cancelled|100"
    )

    for entry in "${categories[@]}"; do
        local category="${entry%%|*}"
        local codes="${entry#*|}"
        echo
        echo "$(gettext "$category")"
        for code in $codes; do
            printf "  %-3s - %s\n" "$code" "$(get_exit_code_description "$code")"
        done
    done

    cat << 'EOF'

═══════════════════════════════════════════════════════════════
You can find the last exit code in the file:
    /var/lib/nvidia-installer/last_exit_code
EOF
}

# 预解析函数，只处理需要在脚本早期生效的参数
# This function does not need i18n support as it runs before language selection.
pre_parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)   AUTO_YES=true ;;
            -q|--quiet) QUIET_MODE=true ;;
            -h|--help)  show_usage; exit 0 ;;
            --show-exit-codes) show_exit_codes; exit 0 ;;
            --lang)     [[ -n "${2:-}" ]] && { LANG_CURRENT="$2"; export NVIDIA_INSTALLER_LANG="$LANG_CURRENT"; shift; } ;;
        esac
        shift
    done
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -t|--type)
                if [[ -z "${2:-}" ]]; then
                    exit_with_code $EXIT_INVALID_ARGS "$(gettext "args.error.missing_value") --type"
                fi
                INSTALL_TYPE="$2"
                shift 2
                ;;
            -m|--modules)
                if [[ -z "${2:-}" ]]; then
                    exit_with_code $EXIT_INVALID_ARGS "$(gettext "args.error.missing_value") --modules"
                fi
                if [[ "$2" == "proprietary" ]]; then
                    USE_OPEN_MODULES=false
                elif [[ "$2" == "open" ]]; then
                    USE_OPEN_MODULES=true
                else
                    exit_with_code $EXIT_INVALID_ARGS "$(gettext "args.error.invalid_module_type") $2 $(gettext "args.info.valid_types")"
                fi
                shift 2
                ;;
            -l|--local)
                USE_LOCAL_REPO=true
                shift
                ;;
            -v|--version)
                if [[ -z "${2:-}" ]]; then
                    exit_with_code $EXIT_INVALID_ARGS "$(gettext "args.error.missing_value") --version"
                fi
                DRIVER_VERSION="$2"
                shift 2
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -f|--force)
                FORCE_REINSTALL=true
                shift
                ;;
            -s|--skip-checks)
                SKIP_EXISTING_CHECKS=true
                shift
                ;;
            --auto-reboot)
                REBOOT_AFTER_INSTALL=true
                shift
                ;;
            --lang)
                if [[ -z "${2:-}" ]]; then
                    exit_with_code $EXIT_INVALID_ARGS "$(gettext "args.error.missing_value") --lang"
                fi
                LANG_CURRENT="$2"
                shift 2
                ;;
            --cleanup)
                cleanup_failed_install
                exit 0
                ;;
            --rollback)
                rollback_installation
                exit 0
                ;;
            --show-exit-codes)
                show_exit_codes
                exit 0
                ;;
            *)
                exit_with_code $EXIT_INVALID_ARGS "$(gettext "args.error.unknown_arg") $1"
                ;;
        esac
    done

    # 处理环境变量
    if [[ "$NVIDIA_INSTALLER_AUTO_YES" == "true" ]]; then
        AUTO_YES=true
    fi
    
    if [[ "$NVIDIA_INSTALLER_QUIET" == "true" ]]; then
        QUIET_MODE=true
    fi
    
    if [[ "$NVIDIA_INSTALLER_FORCE" == "true" ]]; then
        FORCE_REINSTALL=true
    fi
    
    if [[ "$NVIDIA_INSTALLER_REBOOT" == "true" ]]; then
        REBOOT_AFTER_INSTALL=true
    fi
    
    if [[ -n "$NVIDIA_INSTALLER_MODULES" ]]; then
        if [[ "$NVIDIA_INSTALLER_MODULES" == "proprietary" ]]; then
            USE_OPEN_MODULES=false
        elif [[ "$NVIDIA_INSTALLER_MODULES" == "open" ]]; then
            USE_OPEN_MODULES=true
        fi
    fi
    
    if [[ -n "$NVIDIA_INSTALLER_TYPE" ]]; then
        INSTALL_TYPE="$NVIDIA_INSTALLER_TYPE"
    fi

    # 验证安装类型
    if [[ ! "$INSTALL_TYPE" =~ ^(full|compute-only|desktop-only)$ ]]; then
        exit_with_code $EXIT_INVALID_INSTALL_TYPE "$(gettext "args.error.invalid_install_type") $INSTALL_TYPE"
    fi
    
    # 自动化模式下的合理默认值
    if [[ "$AUTO_YES" == "true" ]]; then
        log_debug "$(gettext "args.info.auto_mode_enabled")"
        if [[ "$QUIET_MODE" == "true" ]]; then
            log_debug "$(gettext "args.info.quiet_mode_enabled")"
        fi
    fi
}

# 状态管理函数
create_state_dir() {
    if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
        exit_with_code $EXIT_STATE_DIR_FAILED "$(gettext "state.dir.error.create_state_dir") $STATE_DIR"
    fi
    chmod 755 "$STATE_DIR"
    
    # 创建安装锁，防止并发安装
    create_install_lock
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

# 清理失败的安装状态
cleanup_failed_install() {
    log_info "$(gettext "cleanup.failed.starting")"

    if [[ -f "$STATE_FILE" ]]; then
        log_info "$(gettext "cleanup.failed.previous_state_found")"
        if [[ "$QUIET_MODE" != "true" ]]; then
            cat "$STATE_FILE"
        fi

        if confirm "$(gettext "cleanup.failed.confirm_cleanup")" "N"; then
            rm -f "$STATE_FILE" "$ROLLBACK_FILE"
            log_success "$(gettext "cleanup.failed.state_cleaned")"
        fi
    else
        log_info "$(gettext "cleanup.failed.no_state_found")"
    fi
}

cleanup_after_success() {
    log_info "$(gettext "cleanup.success.starting")"

    # 删除状态文件和回滚文件
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_success "$(gettext "cleanup.success.state_file_deleted") $STATE_FILE"
    fi
    
    if [[ -f "$ROLLBACK_FILE" ]]; then
        rm -f "$ROLLBACK_FILE"
        log_success "$(gettext "cleanup.success.rollback_file_deleted") $ROLLBACK_FILE"
    fi
    
    # 清理临时文件
    cleanup_temp_files

    log_success "$(gettext "cleanup.success.all_states_cleaned")"
}

# 回滚安装
rollback_installation() {
    log_info "$(gettext "rollback.starting")"

    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        exit_with_code $EXIT_ROLLBACK_FILE_MISSING "$(gettext "rollback.error.rollback_file_missing") $ROLLBACK_FILE"
    fi

    log_warning "$(gettext "rollback.warning.changes_will_be_undone")"
    if confirm "$(gettext "rollback.confirm.proceed")" "N"; then
        # 从后往前执行回滚操作
        local rollback_failed=false
        while read -r action; do
            log_info "$(gettext "rollback.info.executing") $action"
            if ! eval "$action"; then
                log_warning "$(gettext "rollback.warning.partial_failure") $action"
                rollback_failed=true
            fi
        done < <(tac "$ROLLBACK_FILE")

        if [[ "$rollback_failed" == "true" ]]; then
            exit_with_code $EXIT_ROLLBACK_FAILED "$(gettext "rollback.error.partial_failure")"
        fi
        
        # 清理状态文件
        rm -f "$STATE_FILE" "$ROLLBACK_FILE"
        log_success "$(gettext "rollback.success")"
    else
        exit_with_code $EXIT_USER_CANCELLED "$(gettext "rollback.error.user_cancelled")"
    fi
}

# 检测操作系统发行版
detect_distro() {
    log_step "$(gettext "detect.os.starting")"

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO_ID=$ID
        DISTRO_VERSION=$VERSION_ID
        DISTRO_CODENAME=${VERSION_CODENAME:-}
        
        # 确定架构
        ARCH=$(uname -m)
        if [[ "$ARCH" == "x86_64" ]]; then
            ARCH="x86_64"
        elif [[ "$ARCH" == "aarch64" ]]; then
            ARCH="sbsa"
        else
            exit_with_code $EXIT_UNSUPPORTED_ARCH "$(gettext "detect.os.error.unsupported_arch") $ARCH"
        fi

        # 确定包管理器家族 (用于动态分派)
        case $DISTRO_ID in
            ubuntu|debian)                                      PKG_FAMILY="deb" ;;
            rhel|rocky|ol|almalinux|centos|fedora|kylin|amzn)   PKG_FAMILY="rpm" ;;
            opensuse*|sles)                                     PKG_FAMILY="suse" ;;
            azurelinux|mariner)                                 PKG_FAMILY="azure" ;;
            *)                                                  PKG_FAMILY="$DISTRO_ID" ;;
        esac

        log_success "$(gettext "detect.os.success") $NAME ($DISTRO_ID $DISTRO_VERSION) [$ARCH]"
    else
        exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "detect.os.error.cannot_detect")"
    fi
}

# ================ GPU ID Database ==================
# {{GPU_IDS}}
# ================ GPU ID Database End ==============


# 检测GPU架构
detect_gpu_architecture() {
    local device_id="$1"
    local architecture="${GPU_ARCH_DB[$device_id]}"
    
    if [[ -n "$architecture" ]]; then
        echo "$architecture"
    else
        echo "Unknown"
    fi
}

# 检查架构是否支持开源模块
is_open_module_supported() {
    local architecture="$1"

    case "$architecture" in
        "Turing"|"Ampere"|"Hopper"|"Ada Lovelace"|"Blackwell")
            return 0  # 支持开源模块
            ;;
        "Kepler"|"Maxwell"|"Pascal"|"Volta")
            return 1  # 需要专有模块
            ;;
        *)
            return 0  # 未知架构，默认使用开源模块
            ;;
    esac
}

# 检查NVIDIA GPU并确定架构兼容性
check_nvidia_gpu() {
    log_step "$(gettext "detect.gpu.starting")"
    
    if ! command -v lspci &> /dev/null; then
        exit_with_code $EXIT_LSPCI_UNAVAILABLE "$(gettext "detect.gpu.error.lspci_missing")"
    fi
    
    if ! lspci | grep -i nvidia > /dev/null 2>&1; then
        exit_with_code $EXIT_NO_NVIDIA_GPU "$(gettext "detect.gpu.error.no_gpu_found")"
    fi

    # 初始化GPU数据库
    init_gpu_database
    
    # 获取所有NVIDIA GPU
    local gpu_count=0
    local has_incompatible_gpu=false
    local detected_architectures=()
    
    while IFS= read -r line; do
        ((++gpu_count))
        local gpu_info=$(echo "$line" | grep -E "(VGA|3D controller)")
        if [[ -n "$gpu_info" ]]; then
            log_success "$(gettext "detect.gpu.success.detected") #$gpu_count: $gpu_info"

            # 提取设备ID
            local pci_address=$(echo "$line" | awk '{print $1}')
            local device_id=$(lspci -s "$pci_address" -nn | grep -oP '10de:\K[0-9a-fA-F]{4}' | tr '[:upper:]' '[:lower:]')

            if [[ -n "$device_id" ]]; then
                local architecture=$(detect_gpu_architecture "$device_id")
                detected_architectures+=("$architecture")
                # 检查模块兼容性
                if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                    if is_open_module_supported "$architecture"; then
                        log_success "GPU #$gpu_count ($architecture) $(gettext "detect.gpu.success.support_open")"
                    else
                        log_error "GPU #$gpu_count ($architecture) $(gettext "detect.gpu.error.not_support_open")"
                        has_incompatible_gpu=true
                    fi
                else
                    log_info "GPU #$gpu_count ($architecture) $(gettext "detect.gpu.info.use_proprietary")"
                fi
            else
                log_warning "GPU #$gpu_count $(gettext "detect.gpu.warning.unknown_device_id")"
                if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                    has_incompatible_gpu=true
                fi
            fi
        fi
    done < <(lspci | grep -i nvidia)
    
    if [[ $gpu_count -eq 0 ]]; then
        exit_with_code $EXIT_NO_NVIDIA_GPU "$(gettext "detect.gpu.error.no_gpu_found")"
    fi
    
    # 处理兼容性问题
    if [[ "$USE_OPEN_MODULES" == "true" ]] && [[ "$has_incompatible_gpu" == "true" ]]; then
        echo
        log_error "$(gettext "detect.gpu.old_gpu_found_warning")"
        echo -e "${RED}$(gettext "detect.gpu.open_support_prompt")${NC}"
        echo "$(gettext "detect.gpu.info.open_support_list")"
        echo "$(gettext "detect.gpu.info.open_unsupport_list")"
        echo

        if ! [[ "$AUTO_YES" == "true" ]]; then
            echo "$(gettext "detect.gpu.incompatible.solution_prompt")"
            echo "$(gettext "detect.gpu.incompatible.solution_option1")"
            echo "$(gettext "detect.gpu.incompatible.solution_option2")"
            echo

            if confirm "$(gettext "detect.gpu.incompatible.confirm")" "Y"; then
                log_info "$(gettext "detect.gpu.incompatible.switch")"
                USE_OPEN_MODULES=false
            else
                log_warning "$(gettext "detect.gpu.incompatible.continue_warning")"
            fi
        else
            # 自动化模式下的默认行为：切换到专有模块
            log_warning "$(gettext "detect.gpu.incompatible.auto_mode_switch")"
            USE_OPEN_MODULES=false
        fi
    fi
    
    # 显示最终配置摘要
    echo
    log_info "$(gettext "detect.gpu.summary.header")"
    printf "%-15s %-20s %-15s\n" "$(gettext "detect.gpu.summary.header.gpu_number")" "$(gettext "detect.gpu.summary.header.architecture")" "$(gettext "detect.gpu.summary.header.module_type")"
    printf "%-15s %-20s %-15s\n" "-------" "--------" "--------"
    
    for i in "${!detected_architectures[@]}"; do
        local arch="${detected_architectures[$i]}"
        local module_type

        if [[ "$USE_OPEN_MODULES" == "true" ]]; then
            if is_open_module_supported "$arch"; then
                module_type=$(gettext "detect.gpu.summary.value.open_module")
            else
                module_type=$(gettext "detect.gpu.summary.value.proprietary_module_fallback")
            fi
        else
            module_type=$(gettext "detect.gpu.summary.value.proprietary_module")
        fi
        
        printf "%-15s %-20s %-15s\n" "#$((i+1))" "$arch" "$module_type"
    done
    
    if [ "$USE_OPEN_MODULES" = true ] && [ "$has_incompatible_gpu" = true ]; then
        echo
        log_warning "$(gettext "detect.gpu.summary.note.fallback")"
    fi
}

# 智能发行版版本检查 - 分派函数 (设置 support_level 和 warning_msg)
# shellcheck disable=SC2329
__check_distro_support_rhel__() {
    case $DISTRO_VERSION in
        8|9|10) support_level="full" ;;
        7) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.rhel7_eol")" ;;
        *) support_level="unsupported"; warning_msg="$(gettext "detect.distro_support.error.unsupported_rhel_version") $DISTRO_VERSION" ;;
    esac
}
# shellcheck disable=SC2329
__check_distro_support_rocky__()    { __check_distro_support_rhel__; }
# shellcheck disable=SC2329
__check_distro_support_ol__()       { __check_distro_support_rhel__; }
# shellcheck disable=SC2329
__check_distro_support_almalinux__() { __check_distro_support_rhel__; }

# shellcheck disable=SC2329
__check_distro_support_fedora__() {
    local version_num=${DISTRO_VERSION}
    if [[ $version_num -ge 39 && $version_num -le 42 ]]; then
        support_level="full"
    elif [[ $version_num -ge 35 && $version_num -lt 39 ]]; then
        support_level="partial"
        warning_msg="Fedora $DISTRO_VERSION $(gettext "detect.distro_support.warning.fedora_unofficial")"
    else
        support_level="unsupported"
        warning_msg="Fedora $DISTRO_VERSION $(gettext "detect.distro_support.error.fedora_incompatible")"
    fi
}

# shellcheck disable=SC2329
__check_distro_support_ubuntu__() {
    case $DISTRO_VERSION in
        20.04|22.04|24.04) support_level="full" ;;
        18.04) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.ubuntu1804_eol")" ;;
        *)
            if [[ -n "$DISTRO_CODENAME" ]]; then
                case $DISTRO_CODENAME in
                    focal|jammy|noble) support_level="full" ;;
                    *) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.ubuntu_maybe_supported") $DISTRO_VERSION ($DISTRO_CODENAME)" ;;
                esac
            else
                support_level="partial"
                warning_msg="$(gettext "detect.distro_support.warning.ubuntu_unspecified") $DISTRO_VERSION"
            fi
            ;;
    esac
}

# shellcheck disable=SC2329
__check_distro_support_debian__() {
    case $DISTRO_VERSION in
        12) support_level="full" ;;
        11) support_level="partial"; warning_msg=$(gettext "detect.distro_support.warning.debian11_needs_tuning") ;;
        *) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.debian_unspecified") $DISTRO_VERSION" ;;
    esac
}

# shellcheck disable=SC2329
__check_distro_support_suse__() {
    if [[ "$DISTRO_VERSION" =~ ^15 ]]; then
        support_level="full"
    else
        support_level="partial"
        warning_msg="$(gettext "detect.distro_support.warning.suse_maybe_supported") $DISTRO_VERSION"
    fi
}

# shellcheck disable=SC2329
__check_distro_support_amzn__() {
    case $DISTRO_VERSION in
        2023) support_level="full" ;;
        2) support_level="partial"; warning_msg=$(gettext "detect.distro_support.warning.amzn2_needs_tuning") ;;
        *) support_level="unsupported"; warning_msg="$(gettext "detect.distro_support.error.unsupported_amzn_version") $DISTRO_VERSION" ;;
    esac
}

# shellcheck disable=SC2329
__check_distro_support_azure__() {
    case $DISTRO_VERSION in
        2.0|3.0) support_level="full" ;;
        *) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.azure_maybe_supported") $DISTRO_VERSION" ;;
    esac
}

# shellcheck disable=SC2329
__check_distro_support_kylin__() {
    case $DISTRO_VERSION in
        10) support_level="full" ;;
        *) support_level="unsupported"; warning_msg=$(gettext "detect.distro_support.error.unsupported_kylin_version") ;;
    esac
}

check_distro_support() {
    log_step "$(gettext "detect.distro_support.starting")"

    local support_level="full"
    local warning_msg=""

    # 动态分派: 先尝试 DISTRO_ID, 再尝试 PKG_FAMILY
    local fn="__check_distro_support_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__check_distro_support_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then
        "$fn"
    else
        support_level="unsupported"
        warning_msg="$(gettext "detect.distro_support.error.unknown_distro") $DISTRO_ID"
    fi

    # 输出支持状态
    case $support_level in
        "full")
            log_success "$(gettext "detect.distro_support.success.fully_supported") $DISTRO_ID $DISTRO_VERSION"
            ;;
        "partial")
            log_warning "$(gettext "detect.distro_support.warning.partially_supported") $warning_msg"
            if ! confirm "$(gettext "detect.distro_support.prompt.confirm.continue_install")" "N"; then
                exit_with_code $EXIT_USER_CANCELLED "$(gettext "detect.distro_support.user_cancelled")"
            fi
            ;;
        "unsupported")
            log_error "$(gettext "detect.distro_support.error.unsupported") $warning_msg"
            echo
            echo "$(gettext "detect.distro_support.info.supported_list_header")"
            echo "- RHEL/Rocky/Oracle Linux: 8, 9, 10"
            echo "- Fedora: 39-42"
            echo "- Ubuntu: 20.04, 22.04, 24.04"
            echo "- Debian: 12"
            echo "- SUSE: 15.x"
            echo "- Amazon Linux: 2023"
            echo "- Azure Linux: 2.0, 3.0"
            echo "- KylinOS: 10"
            echo
            if ! confirm "$(gettext "detect.distro_support.prompt.confirm.force_install")" "N"; then
                exit_with_code $EXIT_UNSUPPORTED_VERSION "$(gettext "exit_code.compatibility.unsupported_version") $DISTRO_ID $DISTRO_VERSION"
            fi
            log_warning "$(gettext "detect.distro_support.warning.force_mode_issues")"
            ;;
    esac
}

# 检查现有NVIDIA驱动安装
check_existing_nvidia_installation() {
    if [[ "$SKIP_EXISTING_CHECKS" == "true" ]]; then
        log_info "$(gettext "detect.existing_driver.skipping_check")"
        return 0
    fi

    log_step "$(gettext "detect.existing_driver.starting")"

    local existing_driver=""
    local installation_method=""
    
    # 检查是否有NVIDIA内核模块
    if lsmod | grep -q nvidia; then
        existing_driver="kernel_module"
        log_warning "$(gettext "detect.existing_driver.warning.kernel_module_loaded")"
        lsmod | grep nvidia
    fi
    
    # 检查包管理器安装的驱动 (动态分派)
    __check_pkg_nvidia_deb__() {
        if dpkg -l | grep -q nvidia-driver; then
            existing_driver="package_manager"; installation_method="apt/dpkg"
            log_warning "$(gettext "detect.existing_driver.warning.pkg_manager_install")"
            dpkg -l | grep nvidia-driver
        fi
    }
    __check_pkg_nvidia_rpm__() {
        if rpm -qa | grep -q nvidia-driver; then
            existing_driver="package_manager"; installation_method="dnf/rpm"
            log_warning "$(gettext "detect.existing_driver.warning.pkg_manager_install")"
            rpm -qa | grep nvidia
        fi
    }
    __check_pkg_nvidia_suse__() {
        if zypper search -i | grep -q nvidia; then
            existing_driver="package_manager"; installation_method="zypper"
            log_warning "$(gettext "detect.existing_driver.warning.pkg_manager_install")"
            zypper search -i | grep nvidia
        fi
    }
    local fn="__check_pkg_nvidia_${PKG_FAMILY}__"
    if declare -F "$fn" > /dev/null 2>&1; then "$fn"; fi
    
    # 检查runfile安装
    if [[ -f /usr/bin/nvidia-uninstall ]]; then
        existing_driver="runfile"
        installation_method="runfile"
        log_warning "$(gettext "detect.existing_driver.warning.runfile_install")"
    fi
    
    # 检查其他PPA或第三方源 (动态分派)
    __check_third_party_ubuntu__() {
        if apt-cache policy | grep -q "graphics-drivers"; then
            log_warning "$(gettext "detect.existing_driver.warning.ppa_found")"
            installation_method="${installation_method:+$installation_method, }graphics-drivers PPA"
        fi
    }
    __check_third_party_fedora__() {
        if dnf repolist | grep -q rpmfusion; then
            log_warning "$(gettext "detect.existing_driver.warning.rpm_fusion_found")"
            installation_method="${installation_method:+$installation_method, }RPM Fusion"
        fi
    }
    local fn="__check_third_party_${DISTRO_ID}__"
    if declare -F "$fn" > /dev/null 2>&1; then "$fn"; fi
    
    # 处理现有安装 (支持自动化)
    if [[ -n "$existing_driver" ]]; then
        echo
        log_error "$(gettext "detect.existing_driver.error.driver_found")"
        echo "$(gettext "detect.existing_driver.info.install_method") $installation_method"
        echo

        if ! [[ "$FORCE_REINSTALL" == "true" ]] && ! [[ "$AUTO_YES" == "true" ]]; then
            echo -e "$(gettext "detect.existing_driver.prompt.user_choice")"
            echo

            local choice=$(select_option "$(gettext "prompt.select_option.please_select")" "1" \
                "$(gettext "prompt.select_option.existing_driver.choice_uninstall")" \
                "$(gettext "prompt.select_option.existing_driver.choice_force")" \
                "$(gettext "prompt.select_option.existing_driver.choice_skip")" \
                "$(gettext "prompt.select_option.existing_driver.choice_exit")")

            case $choice in
                1)
                    uninstall_existing_nvidia_driver "$existing_driver"
                    ;;
                2)
                    log_warning "$(gettext "detect.existing_driver.warning.force_reinstall_mode")"
                    FORCE_REINSTALL=true
                    ;;
                3)
                    log_warning "$(gettext "detect.existing_driver.warning.skip_mode")"
                    SKIP_EXISTING_CHECKS=true
                    ;;
                4)
                    exit_with_code $EXIT_EXISTING_DRIVER_USER_EXIT "$(gettext "detect.existing_driver.exit.user_choice")"
                    ;;
            esac
        elif [[ "$AUTO_YES" == "true" ]] && ! [[ "$FORCE_REINSTALL" == "true" ]]; then
            # 自动化模式下的默认行为：卸载现有驱动
            log_warning "$(gettext "detect.existing_driver.warning.auto_mode_uninstall")"
            uninstall_existing_nvidia_driver "$existing_driver"
        else
            log_warning "$(gettext "detect.existing_driver.warning.force_mode_skip_uninstall")"
        fi
    else
        log_success "$(gettext "detect.existing_driver.success.no_driver_found")"
    fi
}

# 卸载现有NVIDIA驱动
uninstall_existing_nvidia_driver() {
    local driver_type="$1"

    log_step "$(gettext "uninstall.existing_driver.starting")"

    case $driver_type in
        "runfile")
            if [[ -f /usr/bin/nvidia-uninstall ]]; then
                log_info "$(gettext "uninstall.existing_driver.info.using_runfile_uninstaller")"
                /usr/bin/nvidia-uninstall --silent || log_warning "$(gettext "uninstall.existing_driver.warning.runfile_uninstall_incomplete")"
            fi
            ;;
        "package_manager")
            __uninstall_pkg_deb__() { apt remove --purge -y nvidia-* libnvidia-* || true; apt autoremove -y || true; }
            __uninstall_pkg_rpm__() {
                if dnf --version &>/dev/null; then
                    dnf remove -y nvidia-* libnvidia-* || true; dnf autoremove -y || true
                else
                    yum remove -y nvidia-* libnvidia-* || true
                fi
            }
            __uninstall_pkg_suse__() { zypper remove -y nvidia-* || true; }
            local fn="__uninstall_pkg_${PKG_FAMILY}__"
            if declare -F "$fn" > /dev/null 2>&1; then "$fn"; fi
            ;;
    esac
    
    # 清理模块
    if lsmod | grep -q nvidia; then
        log_info "$(gettext "uninstall.existing_driver.info.removing_kernel_modules")"
        rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia || log_warning "$(gettext "uninstall.existing_driver.warning.module_removal_failed")"
    fi
    
    # 清理配置文件
    rm -rf /etc/modprobe.d/*nvidia* /etc/X11/xorg.conf.d/*nvidia* || true

    log_success "$(gettext "uninstall.existing_driver.success")"
}

# 检测Secure Boot状态
check_secure_boot() {
    log_step "$(gettext "secure_boot.check.starting")"

    local secure_boot_enabled=false
    local secure_boot_method=""
    
    # 方法1: 检查/sys/firmware/efi/efivars
    if [[ -d /sys/firmware/efi/efivars ]]; then
        local sb_file
        sb_file=$(compgen -G "/sys/firmware/efi/efivars/SecureBoot-*" | head -n1)
        if [[ -n "$sb_file" && -f "$sb_file" ]]; then
            local secure_boot_value
            secure_boot_value=$(od -An -t u1 "$sb_file" 2>/dev/null | tr -d ' ')
            if [[ "$secure_boot_value" =~ 1$ ]]; then
                secure_boot_enabled=true
                secure_boot_method="efivars"
            fi
        fi
    fi
    
    # 方法2: 使用mokutil命令
    if command -v mokutil &>/dev/null; then
        if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
            secure_boot_enabled=true
            secure_boot_method="mokutil"
        fi
    fi
    
    # 方法3: 检查bootctl命令
    if command -v bootctl &>/dev/null; then
        if bootctl status 2>/dev/null | grep -q "Secure Boot: enabled"; then
            secure_boot_enabled=true
            secure_boot_method="bootctl"
        fi
    fi
    
    # 方法4: 检查dmesg输出
    if dmesg | grep -q "Secure boot enabled"; then
        secure_boot_enabled=true
        secure_boot_method="dmesg"
    fi

    log_debug "Secure Boot $(gettext "secure_boot.check.method"): $secure_boot_method"

    if [[ "$secure_boot_enabled" == "true" ]]; then
        handle_secure_boot_enabled
    else
        log_success "$(gettext "secure_boot.check.disabled_or_unsupported")"
    fi
}

# 处理Secure Boot启用的情况
handle_secure_boot_enabled() {
    echo
    echo -e "${RED}██████████████████████████████████████████████████████████████████████████████${NC}"
    echo -e "${RED}██                          ⚠️  $(gettext "secure_boot.check.warning")  ⚠️                            ██${NC}"
    echo -e "${RED}██████████████████████████████████████████████████████████████████████████████${NC}"
    echo
    log_error "$(gettext "secure_boot.enabled.error_detected")"
    echo
    echo -e "${YELLOW}🚨 $(gettext "secure_boot.enabled.why_is_problem") ${NC}"
    echo -e "$(gettext "secure_boot.enabled.why_is_problem_detail")"
    echo
    echo -e "${GREEN}✅ $(gettext "secure_boot.enabled.solutions")${NC}"
    echo
    echo -e "${BLUE}$(gettext "secure_boot.enabled.solution.disable")${NC}"
    echo -e "$(gettext "secure_boot.enabled.solution.disable_steps")"
    echo
    echo -e "${BLUE}$(gettext "secure_boot.enabled.solution.sign")${NC}"
    echo -e "$(gettext "secure_boot.enabled.solution.sign_steps")"
    echo
    echo -e "${BLUE}$(gettext "secure_boot.enabled.solution.prebuilt")${NC}"
    echo -e "$(gettext "secure_boot.enabled.solution.prebuilt_steps")"
    echo
    echo -e "${YELLOW}$(gettext "secure_boot.enabled.solution.mok_setup")${NC}"
    echo -e "$(gettext "secure_boot.enabled.solution.mok_setup_notice")"
    echo

    # 检查是否已有MOK密钥
    local has_existing_mok=false
    if [[ -f /var/lib/shim-signed/mok/MOK.der ]] || [[ -f /var/lib/dkms/mok.pub ]]; then
        has_existing_mok=true
        echo -e "${GREEN}$(gettext "secure_boot.enabled.sign.detected")${NC}"
    fi
    
    echo -e "${RED}██████████████████████████████████████████████████████████████████████████████${NC}"
    echo -e "${RED}██  $(gettext "secure_boot.enabled.advice_footer")   ██${NC}"
    echo -e "${RED}██████████████████████████████████████████████████████████████████████████████${NC}"
    echo

    if ! [[ "$AUTO_YES" == "true" ]]; then
        echo -e "$(gettext "secure_boot.enabled.choose_action.prompt")"
        echo

        local choice=$(select_option "$(gettext "prompt.select_option.please_select")" "1" \
            "$(gettext "secure_boot.enabled.choice.exit")" \
            "$(gettext "secure_boot.enabled.choice.sign")" \
            "$(gettext "secure_boot.enabled.choice.force")")

        case $choice in
            1)
                log_info "$(gettext "secure_boot.enabled.exit.cancelled_user_fix")"
                echo
                echo -e "$(gettext "secure_boot.enabled.exit.useful_commands")"
                echo
                exit_with_code $EXIT_SECURE_BOOT_USER_EXIT "$(gettext "secure_boot.enabled.exit.user_choice")"
                ;;
            2)
                setup_mok_signing
                ;;
            3)
                log_warning "$(gettext "secure_boot.enabled.warning.user_forced_install")"
                ;;
        esac
    else
        # 自动化模式下的行为
        if [[ "$has_existing_mok" == "true" ]]; then
            log_warning "$(gettext "secure_boot.enabled.warning.auto_mode_existing_mok")"
        else
            exit_with_code $EXIT_SECURE_BOOT_AUTO_FAILED "$(gettext "secure_boot.enabled.error.auto_mode_failure")"
        fi
    fi
}

# 设置MOK密钥签名
setup_mok_signing() {
    log_step "$(gettext "mok.setup.starting")"

    # 检查必要工具
    local missing_tools=()
    for tool in mokutil openssl; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "$(gettext "mok.setup.error.tools_missing") ${missing_tools[*]}"
        echo "$(gettext "mok.setup.error.please_install_tools")"
        case $DISTRO_ID in
            ubuntu|debian)
                echo "sudo apt install mokutil openssl"
                ;;
            rhel|rocky|ol|almalinux|fedora)
                echo "sudo dnf install mokutil openssl"
                ;;
            opensuse*|sles)
                echo "sudo zypper install mokutil openssl"
                ;;
        esac
        exit_with_code $EXIT_MOK_TOOLS_MISSING "$(gettext "mok.setup.error.tools_missing") ${missing_tools[*]}"
    fi
    
    # 检查是否已有MOK密钥
    local mok_key_path=""
    local mok_cert_path=""
    
    # Ubuntu/Debian路径
    if [[ -f /var/lib/shim-signed/mok/MOK.priv ]] && [[ -f /var/lib/shim-signed/mok/MOK.der ]]; then
        mok_key_path="/var/lib/shim-signed/mok/MOK.priv"
        mok_cert_path="/var/lib/shim-signed/mok/MOK.der"
        log_info "$(gettext "mok.setup.info.using_ubuntu_key")"
    # DKMS路径
    elif [[ -f /var/lib/dkms/mok.key ]] && [[ -f /var/lib/dkms/mok.der ]]; then
        mok_key_path="/var/lib/dkms/mok.key"
        mok_cert_path="/var/lib/dkms/mok.der"
        log_info "$(gettext "mok.setup.info.using_dkms_key")"
    else
        # 生成新的MOK密钥
        log_info "$(gettext "mok.setup.info.generating_new_key")"

        # 创建目录
        mkdir -p /var/lib/dkms
        
        # 生成密钥和证书
        if ! openssl req -new -x509 \
            -newkey rsa:2048 \
            -keyout /var/lib/dkms/mok.key \
            -outform DER \
            -out /var/lib/dkms/mok.der \
            -nodes -days 36500 \
            -subj "/CN=NVIDIA Driver MOK Signing Key"; then
            exit_with_code $EXIT_MOK_OPERATION_FAILED "$(gettext "mok.setup.error.generation_failed")"
        fi
        
        # 也生成PEM格式的公钥供参考
        openssl x509 -in /var/lib/dkms/mok.der -inform DER -out /var/lib/dkms/mok.pub -outform PEM
        
        mok_key_path="/var/lib/dkms/mok.key"
        mok_cert_path="/var/lib/dkms/mok.der"

        log_success "$(gettext "mok.setup.success.generation_complete")"
    fi
    
    # 注册MOK密钥
    log_info "$(gettext "mok.setup.info.enrolling_key")"
    echo
    echo -e "${YELLOW}$(gettext "mok.setup.enroll.important_note_header")${NC}"
    echo -e "$(gettext "mok.setup.enroll.note")"
    echo
    
    if ! mokutil --import "$mok_cert_path"; then
        exit_with_code $EXIT_MOK_OPERATION_FAILED "$(gettext "mok.setup.error.enroll_failed")"
    fi

    log_success "$(gettext "mok.setup.success.enroll_queued")"
    echo
    echo -e "${GREEN}$(gettext "mok.setup.next_steps.header")${NC}"
    echo -e "$(gettext "mok.setup.enroll.next_steps")"
    echo
    echo -e "${YELLOW}$(gettext "mok.setup.next_steps.warning_english_interface")${NC}"
    
    # 配置DKMS自动签名
    configure_dkms_signing "$mok_key_path" "$mok_cert_path"
}

# 配置DKMS自动签名
configure_dkms_signing() {
    local key_path="$1"
    local cert_path="$2"

    log_info "$(gettext "dkms.signing.configuring")"

    # 配置DKMS签名工具
    if [[ -f /etc/dkms/framework.conf ]]; then
        # 启用签名工具
        if grep -q "^#sign_tool" /etc/dkms/framework.conf; then
            sed -i 's/^#sign_tool/sign_tool/' /etc/dkms/framework.conf
        elif ! grep -q "^sign_tool" /etc/dkms/framework.conf; then
            echo 'sign_tool="/etc/dkms/sign_helper.sh"' >> /etc/dkms/framework.conf
        fi
    fi
    
    # 创建签名脚本
    cat > /etc/dkms/sign_helper.sh << EOF
#!/bin/sh
/lib/modules/"\$1"/build/scripts/sign-file sha512 "$key_path" "$cert_path" "\$2"
EOF
    
    chmod +x /etc/dkms/sign_helper.sh
    
    # 为NVIDIA特定配置
    echo "SIGN_TOOL=\"/etc/dkms/sign_helper.sh\"" > /etc/dkms/nvidia.conf
    
    save_rollback_info "rm -f /etc/dkms/sign_helper.sh /etc/dkms/nvidia.conf"

    log_success "$(gettext "dkms.signing.success")"
}

# 预安装检查集合
pre_installation_checks() {
    log_step "$(gettext "pre_check.starting")"

    # 检查Secure Boot状态
    check_secure_boot
    
    # 检查根分区空间
    local root_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $root_space -lt 1048576 ]]; then  # 1GB
        log_warning "$(gettext "root.partition.space.insufficient")"
    fi
    
    # 检查是否在虚拟机中运行
    if systemd-detect-virt --quiet; then
        local virt_type=$(systemd-detect-virt)
        log_warning "$(gettext "pre_check.warning.vm_detected") $virt_type"
        echo -e "$(gettext "pre_check.vm.note")"
    fi
    
    # 检查是否有自定义内核
    local kernel_version=$(uname -r)
    if [[ "$kernel_version" =~ (custom|zen|liquorix) ]]; then
        log_warning "$(gettext "pre_check.warning.custom_kernel_detected") $kernel_version"
        echo "$(gettext "pre_check.custom_kernel.note")"
    fi

    log_success "$(gettext "pre_check.success")"
}

# 获取发行版特定的变量 - 分派函数 (设置 DISTRO_REPO 和 ARCH_EXT)
# shellcheck disable=SC2329
__get_distro_vars_rhel__()   { DISTRO_REPO="rhel${DISTRO_VERSION}"; ARCH_EXT="x86_64"; }
# shellcheck disable=SC2329
__get_distro_vars_rocky__()  { __get_distro_vars_rhel__; }
# shellcheck disable=SC2329
__get_distro_vars_ol__()     { __get_distro_vars_rhel__; }
# shellcheck disable=SC2329
__get_distro_vars_almalinux__() { __get_distro_vars_rhel__; }
# shellcheck disable=SC2329
__get_distro_vars_fedora__() { DISTRO_REPO="fedora${DISTRO_VERSION}"; ARCH_EXT="x86_64"; }
# shellcheck disable=SC2329
__get_distro_vars_ubuntu__() { DISTRO_REPO="ubuntu${DISTRO_VERSION//.}"; ARCH_EXT="amd64"; }
# shellcheck disable=SC2329
__get_distro_vars_debian__() { DISTRO_REPO="debian${DISTRO_VERSION}"; ARCH_EXT="amd64"; }
# shellcheck disable=SC2329
__get_distro_vars_opensuse__() { DISTRO_REPO="opensuse15"; ARCH_EXT="x86_64"; }
# shellcheck disable=SC2329
__get_distro_vars_sles__()   { DISTRO_REPO="sles15"; ARCH_EXT="x86_64"; }
# shellcheck disable=SC2329
__get_distro_vars_amzn__()   { DISTRO_REPO="amzn2023"; ARCH_EXT="x86_64"; }
# shellcheck disable=SC2329
__get_distro_vars_azurelinux__() { DISTRO_REPO="azl3"; ARCH_EXT="x86_64"; }
# shellcheck disable=SC2329
__get_distro_vars_mariner__() { DISTRO_REPO="cm2"; ARCH_EXT="x86_64"; }
# shellcheck disable=SC2329
__get_distro_vars_kylin__()  { DISTRO_REPO="kylin10"; ARCH_EXT="x86_64"; }

get_distro_vars() {
    local fn="__get_distro_vars_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__get_distro_vars_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then
        "$fn"
    fi
}

safe_add_repository() {
    local repo_type="$1"
    local repo_url="$2"
    local repo_name="$3"
    local key_url="$4"
    
    case $repo_type in
        "dnf")
            if dnf repolist | grep -q "$repo_name"; then
                log_info "$repo_name $(gettext "repo.add.exists")"
            else
                log_info "$(gettext "repo.add.adding") $repo_name"
                dnf config-manager --add-repo "$repo_url"
                save_rollback_info "dnf config-manager --remove-repo $repo_name"
            fi
            ;;
        "apt")
            if [[ -f "/etc/apt/sources.list.d/$repo_name.list" ]] || grep -q "$repo_url" /etc/apt/sources.list.d/*.list 2>/dev/null; then
                log_info "$(gettext "repo.add.exists")"
            else
                log_info "$(gettext "repo.add.adding") $repo_name"
                if [[ -n "$key_url" ]]; then
                    wget -qO- "$key_url" | gpg --dearmor > "/usr/share/keyrings/$repo_name-keyring.gpg"
                    echo "deb [signed-by=/usr/share/keyrings/$repo_name-keyring.gpg] $repo_url" > "/etc/apt/sources.list.d/$repo_name.list"
                    save_rollback_info "rm -f /etc/apt/sources.list.d/$repo_name.list /usr/share/keyrings/$repo_name-keyring.gpg"
                else
                    echo "deb $repo_url" > "/etc/apt/sources.list.d/$repo_name.list"
                    save_rollback_info "rm -f /etc/apt/sources.list.d/$repo_name.list"
                fi
            fi
            ;;
        "zypper")
            if zypper lr | grep -q "$repo_name"; then
                log_info "$repo_name $(gettext "repo.add.exists")"
            else
                log_info "$(gettext "repo.add.adding") $repo_name"
                zypper addrepo "$repo_url" "$repo_name"
                save_rollback_info "zypper removerepo $repo_name"
            fi
            ;;
    esac
}

safe_install_package() {
    local package_manager="$1"
    shift
    local packages=("$@")
    
    local missing_packages=()
    
    # 检查哪些包未安装
    case $package_manager in
        "dnf"|"yum")
            for pkg in "${packages[@]}"; do
                if ! rpm -q "$pkg" &>/dev/null; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
        "apt")
            for pkg in "${packages[@]}"; do
                if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
        "zypper")
            for pkg in "${packages[@]}"; do
                if ! zypper search -i "$pkg" | grep -q "^i"; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
        "tdnf")
            for pkg in "${packages[@]}"; do
                if ! tdnf list installed "$pkg" &>/dev/null; then
                    missing_packages+=("$pkg")
                fi
            done
            ;;
    esac
    
    # 只安装缺失的包
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_info "$(gettext "pkg_install.info.installing_missing") ${missing_packages[*]}"
        case $package_manager in
            "dnf")
                dnf install -y "${missing_packages[@]}"
                ;;
            "yum")
                yum install -y "${missing_packages[@]}"
                ;;
            "apt")
                apt install -y "${missing_packages[@]}"
                ;;
            "zypper")
                zypper install -y "${missing_packages[@]}"
                ;;
            "tdnf")
                tdnf install -y "${missing_packages[@]}"
                ;;
        esac
        
        # 保存回滚信息
        for pkg in "${missing_packages[@]}"; do
            save_rollback_info "$package_manager remove -y $pkg"
        done
    else
        log_info "$(gettext "pkg_install.info.all_packages_exist")"
    fi
}

# 启用第三方仓库和依赖 - 分派函数
# shellcheck disable=SC2329
__enable_repositories_rhel__() {
    subscription-manager repos --enable=rhel-${DISTRO_VERSION}-for-${ARCH}-appstream-rpms || log_warning "$(gettext "repo.enable.error.rhel_appstream")"
    subscription-manager repos --enable=rhel-${DISTRO_VERSION}-for-${ARCH}-baseos-rpms || log_warning "$(gettext "repo.enable.error.rhel_baseos")"
    subscription-manager repos --enable=codeready-builder-for-rhel-${DISTRO_VERSION}-${ARCH}-rpms || log_warning "$(gettext "repo.enable.error.rhel_crb")"
    if ! rpm -q epel-release &>/dev/null; then
        dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${DISTRO_VERSION}.noarch.rpm"
        save_rollback_info "dnf remove -y epel-release"
    fi
}

# shellcheck disable=SC2329
__enable_repositories_rocky__() {
    if [[ "$DISTRO_VERSION" =~ ^(9|10) ]]; then
        if ! dnf repolist enabled | grep -q crb; then
            dnf config-manager --set-enabled crb
            save_rollback_info "dnf config-manager --set-disabled crb"
        fi
    elif [[ "$DISTRO_VERSION" == "8" ]]; then
        if ! dnf repolist enabled | grep -q powertools; then
            dnf config-manager --set-enabled powertools
            save_rollback_info "dnf config-manager --set-disabled powertools"
        fi
    fi
    safe_install_package "dnf" epel-release
}

# shellcheck disable=SC2329
__enable_repositories_ol__() {
    local crb_repo="ol${DISTRO_VERSION}_codeready_builder"
    local epel_pkg="oracle-epel-release-el${DISTRO_VERSION}"
    if ! dnf repolist enabled | grep -q "$crb_repo"; then
        dnf config-manager --set-enabled "$crb_repo"
        save_rollback_info "dnf config-manager --set-disabled $crb_repo"
    fi
    safe_install_package "dnf" "$epel_pkg"
}

# shellcheck disable=SC2329
__enable_repositories_debian__() {
    if ! grep -q "contrib" /etc/apt/sources.list; then
        if ! is_step_completed "debian_contrib_enabled"; then
            add-apt-repository -y contrib
            save_state "debian_contrib_enabled"
            save_rollback_info "add-apt-repository -r contrib"
        fi
    fi
    if ! is_step_completed "apt_update_after_contrib"; then
        apt update
        save_state "apt_update_after_contrib"
    fi
}

# shellcheck disable=SC2329
__enable_repositories_suse__() {
    if command -v SUSEConnect >/dev/null 2>&1 && ! SUSEConnect -l | grep -q PackageHub; then
        SUSEConnect --product "PackageHub/15/$(uname -m)" || log_warning "$(gettext "repo.enable.error.suse_packagehub")"
        save_rollback_info "SUSEConnect -d --product PackageHub/15/$(uname -m)"
    fi
    if ! is_step_completed "zypper_refresh_after_packagehub"; then
        zypper refresh
        save_state "zypper_refresh_after_packagehub"
    fi
}

# shellcheck disable=SC2329
__enable_repositories_azurelinux__() {
    safe_install_package "tdnf" azurelinux-repos-extended
}

# shellcheck disable=SC2329
__enable_repositories_mariner__() {
    safe_install_package "tdnf" mariner-repos-extended
}

enable_repositories() {
    if is_step_completed "enable_repositories"; then
        log_info "$(gettext "repo.enable.already_done")"
        return 0
    fi

    log_step "$(gettext "repo.enable.starting")"

    # 动态分派: 先尝试 DISTRO_ID, 再尝试 PKG_FAMILY
    local fn="__enable_repositories_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__enable_repositories_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then
        "$fn"
    fi
    
    save_state "enable_repositories"
}

# 安装内核头文件和开发包 - 分派函数
# shellcheck disable=SC2329
__install_kernel_headers_rhel__() {
    if [[ "$DISTRO_VERSION" =~ ^(9|10) ]]; then
        safe_install_package "dnf" kernel-devel-matched kernel-headers
    else
        safe_install_package "dnf" "kernel-devel-$(uname -r)" kernel-headers
    fi
}
# shellcheck disable=SC2329
__install_kernel_headers_rocky__()    { __install_kernel_headers_rhel__; }
# shellcheck disable=SC2329
__install_kernel_headers_ol__()       { __install_kernel_headers_rhel__; }
# shellcheck disable=SC2329
__install_kernel_headers_almalinux__() { __install_kernel_headers_rhel__; }
# shellcheck disable=SC2329
__install_kernel_headers_fedora__() { safe_install_package "dnf" kernel-devel-matched kernel-headers; }
# shellcheck disable=SC2329
__install_kernel_headers_deb__() {
    if ! is_step_completed "apt_update_before_headers"; then
        apt update
        save_state "apt_update_before_headers"
    fi
    safe_install_package "apt" "linux-headers-$(uname -r)"
}
# shellcheck disable=SC2329
__install_kernel_headers_suse__() {
    local variant=$(uname -r | grep -o '\-[^-]*' | sed 's/^-//')
    local version=$(uname -r | sed 's/\-[^-]*$//')
    safe_install_package "zypper" "kernel-${variant:-default}-devel=${version}"
}
# shellcheck disable=SC2329
__install_kernel_headers_amzn__() { safe_install_package "dnf" "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)"; }
# shellcheck disable=SC2329
__install_kernel_headers_azure__() { safe_install_package "tdnf" "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" "kernel-modules-extra-$(uname -r)"; }
# shellcheck disable=SC2329
__install_kernel_headers_kylin__() { safe_install_package "dnf" "kernel-devel-$(uname -r)" kernel-headers; }

install_kernel_headers() {
    if is_step_completed "install_kernel_headers"; then
        log_info "$(gettext "kernel_headers.install.already_done")"
        return 0
    fi

    log_step "$(gettext "kernel_headers.install.starting")"

    local fn="__install_kernel_headers_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__install_kernel_headers_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then
        "$fn"
    fi

    save_state "install_kernel_headers"
}

# 安装本地仓库 - 分派函数 (使用父作用域的 version 和 base_url)
# shellcheck disable=SC2329
__install_local_repository_rpm__() {
    local rpm_file="nvidia-driver-local-repo-${DISTRO_REPO}.${version}.${ARCH_EXT}.rpm"
    log_info "$(gettext "repo.local.setup.downloading") $rpm_file"
    wget -O "/tmp/$rpm_file" "${base_url}/${version}/local_installers/${rpm_file}"
    rpm --install "/tmp/$rpm_file"
}

# shellcheck disable=SC2329
__install_local_repository_deb__() {
    local deb_file="nvidia-driver-local-repo-${DISTRO_REPO}-${version}_${ARCH_EXT}.deb"
    log_info "$(gettext "repo.local.setup.downloading") $deb_file"
    wget -O "/tmp/$deb_file" "${base_url}/${version}/local_installers/${deb_file}"
    dpkg -i "/tmp/$deb_file"
    apt update
    cp "/var/nvidia-driver-local-repo-${DISTRO_REPO}-${version}/nvidia-driver-*-keyring.gpg" /usr/share/keyrings/
}

# shellcheck disable=SC2329
__install_local_repository_suse__() { __install_local_repository_rpm__; }

install_local_repository() {
    log_info "$(gettext "repo.local.setup.starting")"

    local version=${DRIVER_VERSION:-"latest"}
    local base_url="https://developer.download.nvidia.cn/compute/nvidia-driver"

    local fn="__install_local_repository_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__install_local_repository_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then
        "$fn"
    fi
}

# 安装网络仓库 - 分派函数
# shellcheck disable=SC2329
__install_network_repository_rpm__() {
    local repo_url="https://developer.download.nvidia.cn/compute/cuda/repos/${DISTRO_REPO}/${ARCH}/cuda-${DISTRO_REPO}.repo"
    safe_add_repository "dnf" "$repo_url" "cuda-${DISTRO_REPO}"
    if ! is_step_completed "dnf_cache_cleared"; then
        dnf clean expire-cache
        save_state "dnf_cache_cleared"
    fi
}

# shellcheck disable=SC2329
__install_network_repository_deb__() {
    if ! dpkg -l cuda-keyring &>/dev/null; then
        local keyring_url="https://developer.download.nvidia.cn/compute/cuda/repos/${DISTRO_REPO}/${ARCH}/cuda-keyring_1.1-1_all.deb"
        log_info "$(gettext "repo.network.setup.installing_keyring")"
        wget -O /tmp/cuda-keyring.deb "$keyring_url"
        dpkg -i /tmp/cuda-keyring.deb
        save_rollback_info "dpkg -r cuda-keyring"
        rm -f /tmp/cuda-keyring.deb
    else
        log_info "$(gettext "repo.network.setup.keyring_exists")"
    fi
    if ! is_step_completed "apt_update_after_repo"; then
        apt update
        save_state "apt_update_after_repo"
    fi
}

# shellcheck disable=SC2329
__install_network_repository_suse__() {
    local repo_url="https://developer.download.nvidia.cn/compute/cuda/repos/${DISTRO_REPO}/${ARCH}/cuda-${DISTRO_REPO}.repo"
    safe_add_repository "zypper" "$repo_url" "cuda-${DISTRO_REPO}"
    if ! is_step_completed "zypper_refresh_after_repo"; then
        zypper refresh
        save_state "zypper_refresh_after_repo"
    fi
}

# shellcheck disable=SC2329
__install_network_repository_azure__() {
    local repo_url="https://developer.download.nvidia.cn/compute/cuda/repos/${DISTRO_REPO}/${ARCH}/cuda-${DISTRO_REPO}.repo"
    safe_add_repository "dnf" "$repo_url" "cuda-${DISTRO_REPO}"
    if ! is_step_completed "tdnf_cache_cleared"; then
        tdnf clean expire-cache
        save_state "tdnf_cache_cleared"
    fi
}

install_network_repository() {
    log_info "$(gettext "repo.network.setup.starting")"

    local fn="__install_network_repository_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__install_network_repository_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then
        "$fn"
    fi
}

# 添加NVIDIA官方仓库
add_nvidia_repository() {
    if is_step_completed "add_nvidia_repository"; then
        log_info "$(gettext "repo.nvidia.add.already_done")"
        return 0
    fi

    log_step "$(gettext "repo.nvidia.add.starting")"

    get_distro_vars

    if [[ "$USE_LOCAL_REPO" == "true" ]]; then
        install_local_repository
    else
        install_network_repository
    fi
    
    save_state "add_nvidia_repository"
}

# 启用DNF模块 (RHEL 8/9特有)
enable_dnf_modules() {
    case $DISTRO_ID in
        rhel|rocky|ol|almalinux)
            if [[ "$DISTRO_VERSION" =~ ^(8|9) ]]; then
                log_step "$(gettext "dnf_module.enable.starting")"
                if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                    dnf module enable -y nvidia-driver:open-dkms
                else
                    dnf module enable -y nvidia-driver:latest-dkms
                fi
            fi
            ;;
        kylin|amzn)
            log_step "$(gettext "dnf_module.enable.starting")"
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                dnf module enable -y nvidia-driver:open-dkms
            else
                dnf module enable -y nvidia-driver:latest-dkms
            fi
            ;;
    esac
}

# 安装NVIDIA驱动
# shellcheck disable=SC2329
__install_nvidia_driver_rpm__()   { install_nvidia_rpm; }
# shellcheck disable=SC2329
__install_nvidia_driver_deb__()   { install_nvidia_deb; }
# shellcheck disable=SC2329
__install_nvidia_driver_suse__()  { install_nvidia_suse; }
# shellcheck disable=SC2329
__install_nvidia_driver_azure__() { tdnf install -y nvidia-open; }

install_nvidia_driver() {
    log_step "$(gettext "nvidia_driver.install.starting") ($(if $USE_OPEN_MODULES; then echo $(gettext "nvidia_driver.type.open"); else echo $(gettext "nvidia_driver.type.proprietary"); fi), $INSTALL_TYPE)..."

    local fn="__install_nvidia_driver_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__install_nvidia_driver_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then
        "$fn"
    fi
}

# 安装RPM包
install_nvidia_rpm() {
    case $INSTALL_TYPE in
        full)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                if [[ "$DISTRO_ID" =~ ^(rhel|rocky|ol|almalinux)$ && "$DISTRO_VERSION" =~ ^(10)$ ]] || [[ "$DISTRO_ID" == "fedora" ]]; then
                    dnf install -y nvidia-open
                else
                    dnf install -y nvidia-open
                fi
            else
                dnf install -y cuda-drivers
            fi
            ;;
        compute-only)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                dnf install -y nvidia-driver-cuda kmod-nvidia-open-dkms
            else
                dnf install -y nvidia-driver-cuda kmod-nvidia-latest-dkms
            fi
            ;;
        desktop-only)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                dnf install -y nvidia-driver kmod-nvidia-open-dkms
            else
                dnf install -y nvidia-driver kmod-nvidia-latest-dkms
            fi
            ;;
    esac
}

# 安装DEB包
install_nvidia_deb() {
    case $INSTALL_TYPE in
        full)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                apt install -y nvidia-open
            else
                apt install -y cuda-drivers
            fi
            ;;
        compute-only)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                apt install -y nvidia-driver-cuda nvidia-kernel-open-dkms
            else
                apt install -y nvidia-driver-cuda nvidia-kernel-dkms
            fi
            ;;
        desktop-only)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                apt install -y nvidia-driver nvidia-kernel-open-dkms
            else
                apt install -y nvidia-driver nvidia-kernel-dkms
            fi
            ;;
    esac
}

# 安装SUSE包
install_nvidia_suse() {
    case $INSTALL_TYPE in
        full)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                zypper -v install nvidia-open
            else
                zypper -v install cuda-drivers
            fi
            ;;
        compute-only)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                zypper -v install nvidia-compute-G06 nvidia-open-driver-G06
            else
                zypper -v install nvidia-compute-G06 nvidia-driver-G06
            fi
            ;;
        desktop-only)
            if [[ "$USE_OPEN_MODULES" == "true" ]]; then
                zypper -v install nvidia-video-G06 nvidia-open-driver-G06
            else
                zypper -v install nvidia-video-G06 nvidia-driver-G06
            fi
            ;;
    esac
}

# 禁用nouveau驱动
disable_nouveau() {
    log_step "$(gettext "nouveau.disable.starting")"
    
    local need_reboot=false
    local nouveau_active=false
    
    # 检查nouveau是否正在使用
    if lsmod | grep -q "^nouveau"; then
        nouveau_active=true
        log_warning "$(gettext "nouveau.disable.warning.detected_running")"

        # 检查是否有进程正在使用nouveau
        local processes_using_drm=$(lsof /dev/dri/* 2>/dev/null | wc -l)
        if [[ $processes_using_drm -gt 0 ]]; then
            log_warning "$processes_using_drm $(gettext "nouveau.disable.warning.processes_using_drm")"

            # 尝试停止图形相关服务
            log_info "$(gettext "nouveau.disable.info.stopping_display_manager")"

            # 停止显示管理器
            local display_managers=("gdm" "lightdm" "sddm" "xdm" "kdm")
            local stopped_services=()
            
            for dm in "${display_managers[@]}"; do
                if systemctl is-active --quiet "$dm" 2>/dev/null; then
                    log_info "$(gettext "nouveau.disable.info.stop_display_manager") $dm"
                    systemctl stop "$dm" || log_warning "$(gettext "nouveau.disable.warning.failed_stopping_display_manager") $dm"
                    stopped_services+=("$dm")
                    sleep 2
                fi
            done
            
            # 尝试切换到文本模式
            if [[ -n "${stopped_services[*]}" ]]; then
                log_info "$(gettext "nouveau.disable.info.switching_to_text_mode")"
                systemctl isolate multi-user.target 2>/dev/null || true
                sleep 3
            fi
            
            # 保存停止的服务信息，以便后续恢复
            if [[ ${#stopped_services[@]} -gt 0 ]]; then
                echo "${stopped_services[*]}" > "$STATE_DIR/stopped_display_managers"
                save_rollback_info "systemctl start ${stopped_services[*]}"
            fi
        fi
        
        # 尝试卸载nouveau模块
        log_info "$(gettext "nouveau.disable.info.unloading_module")"
        
        # 卸载相关模块（按依赖顺序）
        local modules_to_remove=("nouveau" "ttm" "drm_kms_helper")
        local failed_modules=()
        
        for module in "${modules_to_remove[@]}"; do
            if lsmod | grep -q "^$module"; then
                log_debug "$(gettext "nouveau.disable.info.unload_module"): $module"
                if modprobe -r "$module" 2>/dev/null; then
                    log_success "$(gettext "nouveau.disable.success.module_unloaded") $module"
                else
                    log_warning "$(gettext "nouveau.disable.warning.module_unload_failed") $module"
                    failed_modules+=("$module")
                fi
            fi
        done
        
        # 检查nouveau是否完全卸载
        if lsmod | grep -q "^nouveau"; then
            log_error "$(gettext "nouveau.disable.error.still_running_reboot_needed")"
            need_reboot=true
        else
            log_success "$(gettext "nouveau.disable.success.module_unloaded_all")"
            nouveau_active=false
        fi
    else
        log_info "$(gettext "nouveau.disable.info.not_running")"
    fi
    
    # 创建黑名单文件（无论如何都要创建）
    log_info "$(gettext "nouveau.disable.info.creating_blacklist")"
    cat > /etc/modprobe.d/blacklist-nvidia-nouveau.conf << EOF
# 禁用nouveau开源驱动，由NVIDIA安装脚本生成
blacklist nouveau
options nouveau modeset=0
EOF
    
    save_rollback_info "rm -f /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
    
    # 更新initramfs (动态分派)
    log_info "$(gettext "nouveau.disable.info.updating_initramfs")"
    __update_initramfs_deb__() { update-initramfs -u || log_warning "$(gettext "nouveau.disable.warning.initramfs_update_failed")"; }
    __update_initramfs_rpm__() {
        if command -v dracut &> /dev/null; then
            dracut -f || log_warning "$(gettext "nouveau.disable.warning.initramfs_update_failed")"
        else
            log_warning "$(gettext "nouveau.disable.warning.dracut_missing")"
        fi
    }
    __update_initramfs_suse__() { mkinitrd || log_warning "$(gettext "nouveau.disable.warning.initramfs_update_failed")"; }
    __update_initramfs_azure__() { __update_initramfs_rpm__; }

    local fn="__update_initramfs_${DISTRO_ID}__"
    if ! declare -F "$fn" > /dev/null 2>&1; then
        fn="__update_initramfs_${PKG_FAMILY}__"
    fi
    if declare -F "$fn" > /dev/null 2>&1; then "$fn"; fi
    
    # 如果成功卸载了nouveau，尝试重启显示服务
    if [[ "$nouveau_active" == "false" && -f "$STATE_DIR/stopped_display_managers" ]]; then
        local stopped_services
        read -r stopped_services < "$STATE_DIR/stopped_display_managers"
        
        if [[ -n "$stopped_services" ]]; then
            log_info "$(gettext "nouveau.disable.info.restarting_display_manager")"
            # 切换回图形模式
            systemctl isolate graphical.target 2>/dev/null || true
            sleep 2
            
            # 重启显示管理器
            for dm in $stopped_services; do
                log_info "$(gettext "nouveau.disable.info.restart_display_manager"): $dm"
                systemctl start "$dm" || log_warning "$(gettext "nouveau.disable.warning.restart_failed"): $dm"
            done
            
            rm -f "$STATE_DIR/stopped_display_managers"
        fi
    fi
    
    # 报告状态并决定后续行动
    if [[ "$need_reboot" == "true" ]]; then
        log_warning "$(gettext "nouveau.disable.warning.reboot_required_final")"
        echo "NOUVEAU_NEEDS_REBOOT=true" > "$STATE_DIR/nouveau_status"
        
        echo
        log_error "$(gettext "nouveau.disable.error.reboot_needed_header")"
        echo "$(gettext "nouveau.disable.error.reboot_needed_note")"
        echo

        if [[ "$AUTO_YES" == "true" ]]; then
            log_info "$(gettext "nouveau.disable.info.auto_mode_reboot")"
            save_state "nouveau_disabled_need_reboot"
            reboot
        else
            if confirm "$(gettext "nouveau.disable.confirm.reboot_now")" "Y"; then
                log_info "$(gettext "nouveau.disable.info.rebooting_now")"
                save_state "nouveau_disabled_need_reboot"
                reboot
            else
                exit_with_code $EXIT_NOUVEAU_DISABLE_FAILED "$(gettext "nouveau.disable.exit.user_refused_reboot")"
            fi
        fi
    else
        log_success "$(gettext "nouveau.disable.success.continue_install")"
        echo "NOUVEAU_NEEDS_REBOOT=false" > "$STATE_DIR/nouveau_status"
        
        # 既然nouveau已经成功禁用，就不需要在最终重启逻辑中额外处理
        # 继续正常的安装流程
    fi
}

# 启用persistence daemon
enable_persistence_daemon() {
    log_step "$(gettext "persistence_daemon.enable.starting")"
    
    if systemctl list-unit-files | grep -q nvidia-persistenced; then
        systemctl enable nvidia-persistenced
        log_success "$(gettext "persistence_daemon.enable.success")"
    else
        log_warning "$(gettext "persistence_daemon.enable.warning.service_not_found")"
    fi
}

# 验证安装
verify_installation() {
    log_step "$(gettext "verify.starting")"

    local driver_working=false
    local needs_reboot=false
    
    # 检查驱动版本
    if [[ -f /proc/driver/nvidia/version ]]; then
        local driver_version=$(cat /proc/driver/nvidia/version | head -1)
        log_success "$(gettext "verify.success.driver_loaded"): $driver_version"
    else
        log_warning "$(gettext "verify.warning.module_not_loaded")"
        needs_reboot=true
    fi
    
    # 检查nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        log_success "$(gettext "verify.success.smi_available")"
        log_info "$(gettext "verify.info.testing_driver")"

        if nvidia-smi &> /dev/null; then
            log_success "$(gettext "verify.success.driver_working")"
            driver_working=true
            echo
            nvidia-smi
        else
            log_error "$(gettext "verify.error.smi_failed")"
            needs_reboot=true
        fi
    else
        log_warning "$(gettext "verify.warning.smi_unavailable")"
        needs_reboot=true
    fi
    
    # 检查模块类型
    if lsmod | grep -q nvidia; then
        local module_info=$(lsmod | grep nvidia | head -1)
        log_info "$(gettext "verify.info.loaded_modules"): $module_info"

        # 检查是否是开源模块
        if [[ -f /sys/module/nvidia/version ]]; then
            local module_version=$(cat /sys/module/nvidia/version 2>/dev/null || echo "$(gettext "common.unknown")")
            log_info "$(gettext "verify.info.module_version") $module_version"
        fi
    fi
    
    # 保存验证结果
    if [[ "$driver_working" == "true" ]]; then
        echo "DRIVER_WORKING=true" > "$STATE_DIR/driver_status"
    else
        echo "DRIVER_WORKING=false" > "$STATE_DIR/driver_status"
    fi
    
    if [[ "$needs_reboot" == "true" ]]; then
        echo "NEEDS_REBOOT=true" >> "$STATE_DIR/driver_status"
    else
        echo "NEEDS_REBOOT=false" >> "$STATE_DIR/driver_status"
    fi
}

# 清理安装文件
cleanup() {
    log_step "$(gettext "cleanup.install_files.starting")"

    if [[ "$USE_LOCAL_REPO" == "true" ]]; then
        case $PKG_FAMILY in
            rpm)   dnf remove -y nvidia-driver-local-repo-* 2>/dev/null || true ;;
            deb)   apt remove --purge -y nvidia-driver-local-repo-* 2>/dev/null || true ;;
            suse)  zypper remove -y nvidia-driver-local-repo-* 2>/dev/null || true ;;
            azure) tdnf remove -y nvidia-driver-local-repo-* 2>/dev/null || true ;;
        esac
    fi
    
    # 清理下载的文件
    cleanup_temp_files
    
    # 清理锁文件
    cleanup_lock_files
}

# 显示后续步骤 (更新信息)
show_next_steps() {
    log_success "$(gettext "final.success.header")"
    echo
    echo -e "${GREEN}$(gettext "final.summary.header")${NC}"
    echo -e "- $(gettext "final.summary.distro"): $DISTRO_ID $DISTRO_VERSION\n- $(gettext "final.summary.arch"): $ARCH\n- $(gettext "final.summary.module_type"): $(if $USE_OPEN_MODULES; then echo $(gettext "module.type.open_kernel"); else echo $(gettext "module.type.proprietary_kernel"); fi)\n- $(gettext "final.summary.install_type"): $INSTALL_TYPE\n- $(gettext "final.summary.repo_type"): $(if $USE_LOCAL_REPO; then echo $(gettext "repo.type.local"); else echo $(gettext "repo.type.network"); fi)"
    echo

    # 根据驱动工作状态显示不同的后续步骤
    local driver_working=false
    if [[ -f "$STATE_DIR/driver_status" ]]; then
        local driver_status=$(grep "DRIVER_WORKING" "$STATE_DIR/driver_status" | cut -d= -f2)
        if [[ "$driver_status" == "true" ]]; then
            driver_working=true
        fi
    fi

    echo -e "${YELLOW}$(gettext "final.next_steps.header")${NC}"
    if [[ "$driver_working" == "true" ]]; then
        echo -e "$(gettext "final.next_steps.working.note") '$0 --rollback' "
    else
        echo -e "$(gettext "final.next_steps.not_working.note") '$0 --rollback' "
    fi
    
    # Secure Boot相关提示
    local sb_file_check
    sb_file_check=$(compgen -G "/sys/firmware/efi/efivars/SecureBoot-*" 2>/dev/null | head -n1)
    if [[ -d /sys/firmware/efi/efivars ]] && [[ -n "$sb_file_check" && -f "$sb_file_check" ]]; then
        local sb_value
        sb_value=$(od -An -t u1 "$sb_file_check" 2>/dev/null | tr -d ' ')
        if [[ "$sb_value" =~ 1$ ]]; then
            echo
            echo -e "${YELLOW}$(gettext "final.next_steps.secure_boot.header")${NC}"
            if [[ "$driver_working" == "true" ]]; then
                echo "$(gettext "final.next_steps.secure_boot.working")"
            else
                echo "$(gettext "final.next_steps.secure_boot.error")"
            fi
        fi
    fi
    
    echo
    
    if [[ "$INSTALL_TYPE" == "compute-only" ]]; then
        echo -e "${BLUE}$(gettext "final.notes.compute.header")${NC}"
        echo "$(gettext "final.notes.compute.notes")"
    elif [[ "$INSTALL_TYPE" == "desktop-only" ]]; then
        echo -e "${BLUE}$(gettext "final.notes.desktop.header")${NC}"
        echo -e "$(gettext "final.notes.desktop.notes")"
    fi
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        exit_with_code $EXIT_NO_ROOT "$(gettext "permission.error.root_required") sudo $0"
    fi
}

# 语言选择函数
select_language() {
    # 如果是自动化模式或静默模式，使用默认语言
    if [[ "$AUTO_YES" == "true" ]] || [[ "$QUIET_MODE" == "true" ]]; then
        return 0
    fi
    
    # 如果不是交互式终端，使用默认语言
    if [[ ! -t 0 ]]; then
        return 0
    fi
    
    # 如果已经通过环境变量设置了语言，跳过选择
    if [[ -n "$NVIDIA_INSTALLER_LANG" ]]; then
        LANG_CURRENT="$NVIDIA_INSTALLER_LANG"
        return 0
    fi
    
    echo
    echo "=================================================="
    echo "  Language Selection / 语言选择"
    echo "=================================================="
    echo
    echo "Please select your preferred language:"
    echo "请选择您首选的语言:"
    echo
    echo "1. 中文 (Simplified Chinese)"
    echo "2. English"
    echo
    
    while true; do
        read -p "Please enter your choice (1-2) / 请输入您的选择 (1-2) [default/默认: 1]: " -r choice
        
        # 如果用户直接回车，使用默认值
        if [[ -z "$choice" ]]; then
            choice="1"
        fi
        
        case $choice in
            1)
                LANG_CURRENT="zh_CN"
                echo "已选择中文"
                break
                ;;
            2)
                LANG_CURRENT="en_US"
                echo "English selected"
                break
                ;;
            *)
                echo "Invalid choice, please enter 1 or 2 / 无效选择，请输入1或2"
                ;;
        esac
    done
    echo
}

# 主函数 (添加状态管理和无交互支持)
main() {
    # 预解析命令行参数，在选择语言之前处理一些参数，如--quiet和--auto-yes，这样可以确保在输出任何内容之前就已经设置了这些参数
    pre_parse_arguments "$@"
    # 语言选择（在任何输出之前）
    select_language

    # 检测终端环境，如果不是TTY则自动启用静默模式
    if [[ ! -t 0 ]] && [[ "$QUIET_MODE" != "true" ]]; then
        log_info "$(gettext "main.info.non_interactive_quiet_mode")"
        QUIET_MODE=true
    fi

    if ! [[ "$QUIET_MODE" == "true" ]]; then
        echo -e "${GREEN}"
        echo "=============================================="
        echo "  $(gettext "main.header.title") v${SCRIPT_VERSION}"
        if [[ "$AUTO_YES" == "true" ]]; then
            echo "  $(gettext "main.header.auto_mode_subtitle")"
        fi
        echo "=============================================="
        echo -e "${NC}"
    fi
    
    # 检查root权限
    check_root

    # 创建状态目录
    create_state_dir

    # 解析命令行参数
    parse_arguments "$@"
    
    # 检查上次安装状态
    local last_state=$(get_last_state)
    if [[ -n "$last_state" && "$last_state" != "installation_completed" ]]; then
        echo
        log_warning "$(gettext "main.resume.warning_incomplete_state_found") $last_state"
        if ! [[ "$AUTO_YES" == "true" ]] && confirm "$(gettext "main.resume.confirm_resume_install")" "N"; then
            log_info "$(gettext "main.resume.info_resuming")"
        else
            log_info "$(gettext "main.resume.info_restarting")"
            rm -f "$STATE_FILE" "$ROLLBACK_FILE"
        fi
    fi
    
    # 检测系统环境
    if ! is_step_completed "detect_distro"; then
        detect_distro
        save_state "detect_distro"
    fi
    
    if ! is_step_completed "check_distro_support"; then
        check_distro_support
        save_state "check_distro_support"
    fi
    
    if ! is_step_completed "check_nvidia_gpu"; then
        check_nvidia_gpu
        save_state "check_nvidia_gpu"
    fi
    
    if ! is_step_completed "check_existing_installation"; then
        check_existing_nvidia_installation
        save_state "check_existing_installation"
    fi
    
    if ! is_step_completed "pre_installation_checks"; then
        pre_installation_checks
        save_state "pre_installation_checks"
    fi
    
    # 显示安装配置
    if ! is_step_completed "show_config"; then
        echo
        echo -e "${PURPLE}$(gettext "main.config_summary.header")${NC}"
        echo "- $(gettext "main.config_summary.distro") $DISTRO_ID $DISTRO_VERSION [$ARCH]"
        echo "- $(gettext "main.config_summary.module_type") $(if $USE_OPEN_MODULES; then echo $(gettext "module.type.open_kernel"); else echo $(gettext "module.type.proprietary_kernel"); fi)"
        echo "- $(gettext "main.config_summary.install_type") $INSTALL_TYPE"
        echo "- $(gettext "main.config_summary.repo_type") $(if $USE_LOCAL_REPO; then echo $(gettext "repo.type.local"); else echo $(gettext "repo.type.network"); fi)"
        echo "- $(gettext "main.config_summary.auto_mode") $(if $AUTO_YES; then echo $(gettext "common.yes"); else echo $(gettext "common.no"); fi)"
        echo "- $(gettext "main.config_summary.force_reinstall") $(if $FORCE_REINSTALL; then echo $(gettext "common.yes"); else echo $(gettext "common.no"); fi)"
        echo "- $(gettext "main.config_summary.auto_reboot") $(if $REBOOT_AFTER_INSTALL; then echo $(gettext "common.yes"); else echo $(gettext "common.no"); fi)"
        echo

        if ! [[ "$AUTO_YES" == "true" ]] && ! [[ "$FORCE_REINSTALL" == "true" ]] && ! [[ "$SKIP_EXISTING_CHECKS" == "true" ]]; then
            if ! confirm "$(gettext "main.config_summary.confirm")" "Y"; then
                exit_with_code $EXIT_USER_CANCELLED "$(gettext "main.config_summary.user_cancel")"
            fi
        fi
        save_state "show_config"
    fi
    
    # 开始安装过程
    echo
    log_info "$(gettext "main.install.starting")"

    # 安装内核头文件
    install_kernel_headers
    
    # 启用仓库和依赖
    enable_repositories
    
    # 添加NVIDIA仓库
    add_nvidia_repository
    
    # 启用DNF模块 (如需要)
    if ! is_step_completed "enable_dnf_modules"; then
        enable_dnf_modules
        save_state "enable_dnf_modules"
    fi
    
    # 禁用nouveau驱动
    if ! is_step_completed "disable_nouveau"; then
        disable_nouveau
        save_state "disable_nouveau"
    fi
    
    # 安装NVIDIA驱动
    if ! is_step_completed "install_nvidia_driver"; then
        install_nvidia_driver
        save_state "install_nvidia_driver"
    fi
    
    # 启用persistence daemon
    if ! is_step_completed "enable_persistence_daemon"; then
        enable_persistence_daemon
        save_state "enable_persistence_daemon"
    fi
    
    # 验证安装
    if ! is_step_completed "verify_installation"; then
        verify_installation
        save_state "verify_installation"
    fi
    
    # 清理安装文件
    if ! is_step_completed "cleanup"; then
        cleanup
        save_state "cleanup"
    fi
    
    # 标记安装完成
    save_state "installation_completed"
    
    # 显示后续步骤
    show_next_steps
    
    # 检查是否需要重启系统
    local nouveau_needs_reboot=false
    local driver_needs_reboot=false
    local driver_working=false
    
    # 检查nouveau状态
    if [[ -f "$STATE_DIR/nouveau_status" ]]; then
        local nouveau_status=$(grep "NOUVEAU_NEEDS_REBOOT" "$STATE_DIR/nouveau_status" | cut -d= -f2)
        if [[ "$nouveau_status" == "true" ]]; then
            nouveau_needs_reboot=true
        fi
    fi
    
    # 检查驱动工作状态
    if [[ -f "$STATE_DIR/driver_status" ]]; then
        local driver_status=$(grep "DRIVER_WORKING" "$STATE_DIR/driver_status" | cut -d= -f2)
        local needs_reboot_status=$(grep "NEEDS_REBOOT" "$STATE_DIR/driver_status" | cut -d= -f2)
        
        if [[ "$driver_status" == "true" ]]; then
            driver_working=true
        fi
        
        if [[ "$needs_reboot_status" == "true" ]]; then
            driver_needs_reboot=true
        fi
    fi
    
    echo
    # 根据驱动实际工作状态决定重启行为
    if [[ "$driver_working" == "true" ]]; then
        # 驱动正常工作，不需要重启
        log_success "$(gettext "main.reboot_logic.success_no_reboot_needed")"
        echo "$(gettext "main.reboot_logic.success_smi_passed")"

        if [[ "$REBOOT_AFTER_INSTALL" == "true" ]]; then
            log_info "$(gettext "main.reboot_logic.info_rebooting_on_user_request")"
            log_info "$(gettext "main.reboot_logic.info_rebooting_now")"
            cleanup_after_success
            reboot
        elif [[ "$AUTO_YES" == "true" ]]; then
            log_success "$(gettext "main.reboot_logic.success_auto_mode_no_reboot")"
            cleanup_after_success
        else
            # 交互模式，询问用户是否要重启（但不建议）
            if confirm "$(gettext "main.reboot_logic.confirm_optional_reboot")" "N"; then
                log_info "$(gettext "main.reboot_logic.info_rebooting_now")"
                cleanup_after_success
                reboot
            else
                log_info "$(gettext "main.reboot_logic.info_reboot_skipped")"
                cleanup_after_success
            fi
        fi
    else
        # 驱动未正常工作，需要重启
        log_warning "$(gettext "main.reboot_logic.warning_reboot_required")"
        echo "$(gettext "main.reboot_logic.warning_smi_failed_reboot_required")"

        if [[ "$nouveau_needs_reboot" == "true" ]]; then
            echo "$(gettext "main.reboot_logic.reason_nouveau")"
        elif [[ "$driver_needs_reboot" == "true" ]]; then
            echo "$(gettext "main.reboot_logic.reason_module_load")"
        fi
        
        if [[ "$REBOOT_AFTER_INSTALL" == "true" ]]; then
            log_info "$(gettext "main.reboot_logic.info_auto_mode_rebooting")"
            rm -f "$STATE_FILE" "$ROLLBACK_FILE" "$STATE_DIR/nouveau_status" "$STATE_DIR/driver_status"
            cleanup_lock_files
            reboot
        elif [[ "$AUTO_YES" == "true" ]]; then
            log_warning "$(gettext "main.reboot_logic.warning_manual_reboot_needed")"
            log_info "$(gettext "main.reboot_logic.info_verify_after_reboot")"
            cleanup_lock_files
        else
            if confirm "$(gettext "main.reboot_logic.confirm_reboot_now")" "Y"; then
                log_info "$(gettext "main.reboot_logic.info_rebooting_now")"
                rm -f "$STATE_FILE" "$ROLLBACK_FILE" "$STATE_DIR/nouveau_status" "$STATE_DIR/driver_status"
                cleanup_lock_files
                reboot
            else
                log_warning "$(gettext "main.reboot_logic.warning_manual_reboot_needed")"
                log_info "$(gettext "main.reboot_logic.info_verify_after_reboot")"
                # 保留状态文件供用户查看
                cleanup_lock_files
            fi
        fi
    fi
}

# 运行主函数
main "$@"
