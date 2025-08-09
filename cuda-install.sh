#!/bin/bash

set -eo pipefail

__log() {
    local level="$1"
    shift

    if [ "$VERBOSE" -eq 0 ] && [ "$level" == "DEBUG" ]; then
        return 0
    fi
    if [ "$QUIET" -eq 1 ] && [ "$level" != "ERROR" ]; then
        return 0
    fi

    local C_RESET='\033[0m'
    local C_RED='\033[0;31m'
    local C_YELLOW='\033[0;33m'
    local C_BLUE='\033[0;34m'
    local C_GRAY='\033[0;37m'

    local colored_level
    case "$level" in
    "DEBUG") colored_level="${C_GRAY}$level${C_RESET}" ;;
    "INFO") colored_level="${C_BLUE}$level${C_RESET}" ;;
    "WARN") colored_level="${C_YELLOW}$level${C_RESET}" ;;
    "ERROR") colored_level="${C_RED}$level${C_RESET}" ;;
    *) colored_level="$level" ;;
    esac

    local message
    message="[$(date +'%Y-%m-%d %H:%M:%S')] [$colored_level] $*"

    echo -e "$message" >&2
}

panic() {
    __log "ERROR" "$*"
    exit 1
}

warn() {
    __log "WARN" "$*"
}

info() {
    __log "INFO" "$*"
}

debug() {
    __log "DEBUG" "$*"
}

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
    *) panic "Unsupported distro ID: $ID" ;;
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
        *) panic "Unsupported Debian version: $VERSION_ID" ;;
        esac
        ;;
    "ubuntu")
        case "$VERSION_ID" in
        "12.04") echo "1204" ;;
        "12.10") echo "1210" ;;
        "13.04") echo "1304" ;;
        "14.04") echo "1404" ;;
        "14.10") echo "1410" ;;
        "15.04") echo "1504" ;;
        "16.04") echo "1604" ;;
        "17.04") echo "1704" ;;
        "17.10") echo "1710" ;;
        "18.04") echo "1804" ;;
        "18.10") echo "1810" ;;
        "20.04") echo "2004" ;;
        "22.04") echo "2204" ;;
        "24.04") echo "2404" ;;
        *) panic "Unsupported Ubuntu version: $VERSION_ID" ;;
        esac
        ;;
    "rhel" | "rocky" | "ol")
        case "$VERSION_ID" in
        "6") echo "6" ;;
        "7") echo "7" ;;
        "8") echo "8" ;;
        "9") echo "9" ;;
        "10") echo "10" ;;
        *) panic "Unsupported RHEL/Rocky Linux/Oracle Linux version: $VERSION_ID" ;;
        esac
        ;;
    "fedora")
        case "$VERSION_ID" in
        "18") echo "18" ;;
        "19") echo "19" ;;
        "20") echo "20" ;;
        "21" | "22") echo "21" ;;
        "23" | "24") echo "23" ;;
        "25" | "26") echo "25" ;;
        "27" | "28") echo "27" ;;
        "29" | "30" | "31") echo "29" ;;
        "32") echo "32" ;;
        "33") echo "33" ;;
        "34") echo "34" ;;
        "35") echo "35" ;;
        "36") echo "36" ;;
        "37" | "38") echo "37" ;;
        "39") echo "39" ;;
        "40") echo "40" ;;
        "41" | "42") echo "41" ;;
        *) panic "Unsupported Fedora version: $VERSION_ID" ;;
        esac
        ;;
    "sles" | "opensuse")
        case "$VERSION_ID" in
        "15"*) echo "15" ;;
        *) panic "Unsupported SLES/OpenSUSE version: $VERSION_ID" ;;
        esac
        ;;
    *)
        panic "Unsupported distro ID: $distro_id"
        ;;
    esac
}

map_arch() {
    local __arch
    __arch="$(arch)"

    case "$__arch" in
    "x86_64") echo "x86_64" ;;
    "arm64" | "aarch64") echo "arm64" ;;
    *) panic "Unsupported architecture: $__arch" ;;
    esac
}

detect_package_manager() {
    info "Detecting package manager"

    case "$distro_id" in
    debian | ubuntu)
        if command -v apt &>/dev/null; then
            echo "apt"
        else
            panic "apt not found. Cannot determine package manager."
        fi
        ;;
    rhel | fedora | rocky | ol)
        if command -v dnf &>/dev/null; then
            echo "dnf"
        elif command -v yum &>/dev/null; then
            echo "yum"
        else
            panic "Neither dnf nor yum found. Cannot determine package manager."
        fi
        ;;
    opensuse | sles)
        if command -v zypper &>/dev/null; then
            echo "zypper"
        else
            panic "zypper not found. Cannot determine package manager."
        fi
        ;;
    *)
        panic "Unsupported distro: $distro_id. Cannot determine package manager."
        ;;
    esac
    return 0
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
    info "Installing package(s): ${*}"
    local fn="__pm_inst_${pm}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn" "${@}"
    else
        panic "Unsupported package manager: $pm"
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
    info "Querying package: ${*}"
    local fn="__pm_query_${pm}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn" "${@}"
    else
        panic "Unsupported package manager: $pm"
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
    local fn="__preinstall_rhel_${distro_version}__"
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
    info "Performing pre-installation"

    local fn="__preinstall_${distro_id}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn"
    else
        info "No pre-installation step required for ${distro_id}"
    fi
}

# shellcheck disable=SC2329
__addrepo_debian__() {
    local temp_dir
    temp_dir=$(mktemp -d cuda-repo-XXXXXX)

    $DRY_RUN wget "${repo_url}/cuda-keyring_1.1-1_all.deb" -O "$temp_dir/cuda-keyring_1.1-1_all.deb"
    $DRY_RUN env DEBIAN_FRONTEND=noninteractive dpkg -i "$temp_dir/cuda-keyring_1.1-1_all.deb"
    $DRY_RUN rm -rf "$temp_dir"
}

# shellcheck disable=SC2329
__addrepo_ubuntu__() {
    __addrepo_debian__
}

# shellcheck disable=SC2329
__addrepo_fedora__() {
    $DRY_RUN dnf config-manager --add-repo "${repo_url}/cuda-${distro}.repo"
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
}

# shellcheck disable=SC2329
__addrepo_opensuse__() {
    __addrepo_sles__
}

addrepo() {
    info "Adding repository for CUDA Toolkit"

    local fn="__addrepo_${distro_id}__"
    if declare -F "$fn" &>/dev/null; then
        "$fn"
    else
        info "No add-repository step required for ${distro_id}"
    fi
}

select_cuda_version() {
    local callback_variable_name="$1"
    info "Selecting CUDA version interactively"
    local versions
    versions="$(pm_query "^cuda-[0-9]+-[0-9]+" | sed -E 's/^cuda-(.+)$/\1/' | sort -u)"
    debug "pm_query returned: $versions"

    if [[ -z "$versions" ]]; then
        panic "No available CUDA versions found in the repository."
    fi

    # shellcheck disable=SC2206
    version_array=( $versions )
    for v in "${version_array[@]}"; do
        debug "Found available CUDA version: $v"
    done

    echo "=================================================="
    echo "Available CUDA versions:"
    select version in "${version_array[@]}"; do
        if [[ -n "$version" ]]; then
            eval "$callback_variable_name=\"$version\""
            break
        fi
    done
}

install_cuda() {
    debug "Begin to install CUDA Toolkit"
    if [[ "$INSTALL_TYPE" == "cuda" || "$INSTALL_TYPE" == "all" ]]; then
        info "Installing CUDA Toolkit"
        if [[ "$CUDA_VERSION" == "auto" ]]; then
            pm_inst cuda
        elif [[ -n "$CUDA_VERSION" ]]; then
            pm_inst "cuda-$CUDA_VERSION"
        else
            info "No specific CUDA version provided, selecting interactively"
            local __ver
            select_cuda_version __ver
            pm_inst "cuda-$__ver"
        fi
    else 
        info "Skipping CUDA Toolkit installation as per INSTALL_TYPE: $INSTALL_TYPE"
    fi
}

install_ctk() {
    debug "Begin to install NVIDIA Container Toolkit"
    if [[ "$INSTALL_TYPE" == "ctk" || "$INSTALL_TYPE" == "all" ]]; then
        info "Installing NVIDIA Container Toolkit"
        pm_inst nvidia-container-toolkit
    else 
        info "Skipping NVIDIA Container Toolkit installation as per INSTALL_TYPE: $INSTALL_TYPE"
    fi
}

main() {
    debug "Starting CUDA installation script"

    debug "Checking for root privileges"
    if [ "$EUID" -ne 0 ]; then
        debug "Current EUID: $EUID"
        warn "This script must be run as root. Please retry with sudo."
    fi

    if [ -f "/etc/os-release" ]; then
        debug "Loading OS release information from /etc/os-release"
        # shellcheck disable=SC1091
        . /etc/os-release
    elif [ -f "/usr/lib/os-release" ]; then
        debug "Loading OS release information from /usr/lib/os-release"
        # shellcheck disable=SC1091
        . /usr/lib/os-release
    else
        panic "Cannot determine OS release information. Please ensure /etc/os-release or /usr/lib/os-release exists."
    fi

    local distro_id
    distro_id="$(map_distro_id)"
    debug "Mapped distro ID: $distro_id"

    local distro_version
    distro_version="$(map_distro_version)"
    debug "Mapped distro version: $distro_version"

    local distro
    distro="${distro_id}${distro_version}"
    info "Detected distro: $distro"

    local arch
    arch="$(map_arch)"
    info "Detected architecture: $arch"

    local repo_url="${NVIDIA_REPO_BASE_URL}/${distro}/${arch}"
    info "Using repository base URL: $repo_url"

    local pm=
    pm="$(detect_package_manager)"
    info "Using package manager: $pm"

    preinstall
    addrepo
    install_cuda
    install_ctk

    exit 0
}

help() {
    debug "Show help message"
    cat <<EOF
Install NVIDIA CUDA Toolkit

Usage: $(basename "$0") [OPTIONS]

Currently supported distros: 
    Debian, Ubuntu, Fedora, RHEL, Rocky Linux, Oracle Linux, SLES, OpenSUSE

Options:
    -h, --help      Show this help message and exit
    -v, --verbose   Enable verbose output
    -q, --quiet     Enable quiet output
    -n, --dry-run   Enable dry run mode (most changes won't be made)
    --type=<type>   Specify installation type: 'cuda', 'ctk', 'all', 'none' [Default: 'cuda']
                    'cuda'  Install CUDA Toolkit only
                    'ctk'   Install NVIDIA Container Toolkit only
                    'all'   Install both CUDA and Container Toolkits
                    'none'  Do not install anything (configure repository only)
    --cuda-version=<version> Specify CUDA version to install
                    <version>  Specific version to install (e.g. '12-9')
                    'auto'  Automatically detect and install the latest supported version
                    leave empty to select interactively
    --use-cn-cdn    Replace NVIDIA_REPO_BASE_URL with "https://developer.download.nvidia.cn"

Environment Variables:
    NVIDIA_REPO_BASE_URL    Base URL for the NVIDIA repository 
                            [Default: "https://developer.download.nvidia.com/compute/cuda/repos"]
    TMPDIR                  Temporary directory for storing downloaded files

EOF
    exit 0
}

__main() {
    local VERBOSE=0
    local QUIET=0
    local NVIDIA_REPO_BASE_URL="${NVIDIA_REPO_BASE_URL:-"https://developer.download.nvidia.com/compute/cuda/repos"}"
    local INSTALL_TYPE="cuda"
    local DRY_RUN=
    local CUDA_VERSION=

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            help
            ;;
        -v | --verbose)
            VERBOSE=1
            debug "Verbose mode enabled" # Show debug message after enabling verbose mode
            ;;
        -q | --quiet)
            debug "Quiet mode enabled"
            QUIET=1
            ;;
        -n | --dry-run)
            debug "Dry run mode enabled"
            DRY_RUN="echo"
            ;;
        --type=*)
            INSTALL_TYPE="${1#*=}"
            if [[ "xx${INSTALL_TYPE}xx" =~ ^xx(cuda|ctk|all|none)xx$ ]]; then
                panic "Invalid install type: $INSTALL_TYPE. Supported types are 'cuda', 'ctk', 'all', 'none'."
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
        *)
            panic "Unknown option: $1"
            ;;
        esac
        shift
    done

    main
}

__main "${@}"
