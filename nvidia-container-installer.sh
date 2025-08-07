#!/bin/bash

# NVIDIA Container Toolkit 全自动化安装脚本
# NVIDIA Container Toolkit One-Click Installer

# Author: PEScn @ EM-GeekLab with Claude AI Assistant
# Modified: 2025-08-06
# License: Apache-2.0
# GitHub: https://github.com/EM-GeekLab/nvidia-driver-installer

# Base on NVIDIA CTK Installation Guide: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
# Supports Ubuntu, CentOS, SUSE, RHEL, Fedora, Amazon Linux, Azure Linux and other distributions.
# This script need `root` privileges to run, or use `sudo` to run it.

# ==============================================================================
# Usage | 用法
# ==============================================================================
# 1. download the script | 下载脚本
#
#   $ curl -sSL https://raw.githubusercontent.com/EM-GeekLab/nvidia-driver-installer/main/nvidia-container-install.sh -o nvidia-container-install.sh
#
# 2. [Optional] verify the script's content | 【可选】验证脚本内容
#
#   $ cat nvidia-container-install.sh
#
# 3. run the script either as root, or using sudo to perform the installation. | 以 root 权限或使用 sudo 运行脚本进行安装
#
#   $ sudo bash nvidia-container-install.sh
#
# ==============================================================================
# 
# Dependencies | 依赖项 : Docker, NVIDIA Driver
# -----------------------------------------------------------------------------
# If you don't have Docker and NVIDIA Driver installed, please install them first:
# 
# 1. download the script | 下载脚本
#   $ curl -sSL https://raw.githubusercontent.com/EM-GeekLab/nvidia-driver-installer/main/nvidia-install.sh -o nvidia-install.sh
# 2. run the script | 运行脚本
#   $ sudo bash nvidia-install.sh
#
# ==============================================================================

set -e # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 全局变量
AUTOMATED_MODE=false
FORCE_INSTALL=false
SKIP_DOCKER_USER_GROUP=false
SKIP_VERIFICATION=true        # 默认跳过拉取镜像验证
RUN_DOCKER_VERIFICATION=false # 新增：是否运行 Docker 镜像验证
INSTALL_EXPERIMENTAL=false
CUSTOM_VERSION=""
QUIET_MODE=false
USE_CHINA_MIRROR=false # 新增：是否使用中国镜像加速
LOG_FILE="/tmp/nvidia-toolkit-install.log"

# 锁文件和状态文件
LOCK_FILE="/tmp/nvidia-toolkit-install.lock"
STATE_FILE="/tmp/nvidia-toolkit-install.state"
PID=$$

# 镜像配置
NVIDIA_REPO_BASE="https://nvidia.github.io/libnvidia-container"
CHINA_NVIDIA_REPO_BASE="https://mirrors.cloud.tencent.com/libnvidia-container"
DOCKER_REGISTRY="" # 默认使用官方 registry
CHINA_DOCKER_REGISTRY="docker.m.daocloud.io"

# 系统信息变量
OS_ID=""
OS_VERSION_ID=""
OS_PRETTY_NAME=""
PACKAGE_MANAGER=""
NVIDIA_CONTAINER_TOOLKIT_VERSION=""

# 使用说明
show_usage() {
    cat <<'EOF'
NVIDIA Container Toolkit 全自动化安装脚本

用法: 
    ./install_nvidia_toolkit.sh [选项]

选项:
    -y, --yes                     全自动化模式（无交互）
    -f, --force                    强制安装（跳过某些检查）
    -q, --quiet                    安静模式（减少输出）
    -s, --skip-docker-group        跳过将用户添加到 docker 组
    --enable-verification          启用 Docker 镜像验证（默认关闭）
    --disable-verification         禁用所有验证
    -e, --experimental             安装实验版本
    --version VERSION              安装指定版本（默认: 1.17.8-1）
    --china-mirror                 使用中国镜像加速（腾讯云镜像）
    --log-file FILE               指定日志文件（默认: /tmp/nvidia-toolkit-install.log）
    -h, --help                     显示此帮助信息

自动化部署示例:
    # 完全自动化安装
    ./install_nvidia_toolkit.sh --yes --quiet

    # 中国大陆环境推荐（使用镜像加速）
    ./install_nvidia_toolkit.sh --yes --china-mirror --quiet

    # 强制安装并启用完整验证
    ./install_nvidia_toolkit.sh --yes --force --enable-verification

    # 容器环境部署（跳过所有验证）
    ./install_nvidia_toolkit.sh --yes --disable-verification

    # 安装实验版本
    ./install_nvidia_toolkit.sh --yes --experimental

    # 指定版本安装
    ./install_nvidia_toolkit.sh --yes --version "1.16.0-1"

环境变量支持:
    NVIDIA_TOOLKIT_AUTO=true       等同于 --yes
    NVIDIA_TOOLKIT_FORCE=true      等同于 --force
    NVIDIA_TOOLKIT_QUIET=true      等同于 --quiet
    NVIDIA_TOOLKIT_VERSION=x.x.x   等同于 --version
    NVIDIA_TOOLKIT_EXPERIMENTAL=true  等同于 --experimental
    NVIDIA_TOOLKIT_CHINA_MIRROR=true  等同于 --china-mirror

独立验证脚本:
    # 单独运行 Docker GPU 验证
    ./install_nvidia_toolkit.sh --verify-only

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -y | --yes)
            AUTOMATED_MODE=true
            shift
            ;;
        -f | --force)
            FORCE_INSTALL=true
            shift
            ;;
        -q | --quiet)
            QUIET_MODE=true
            shift
            ;;
        -s | --skip-docker-group)
            SKIP_DOCKER_USER_GROUP=true
            shift
            ;;
        --enable-verification)
            RUN_DOCKER_VERIFICATION=true
            SKIP_VERIFICATION=false
            shift
            ;;
        --disable-verification)
            RUN_DOCKER_VERIFICATION=false
            SKIP_VERIFICATION=true
            shift
            ;;
        --verify-only)
            # 特殊模式：仅运行验证
            verify_docker_gpu_access
            exit $?
            ;;
        -e | --experimental)
            INSTALL_EXPERIMENTAL=true
            shift
            ;;
        --version)
            CUSTOM_VERSION="$2"
            shift 2
            ;;
        --china-mirror)
            USE_CHINA_MIRROR=true
            shift
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -h | --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            show_usage
            exit 1
            ;;
        esac
    done

    # 检查环境变量
    [[ "${NVIDIA_TOOLKIT_AUTO}" == "true" ]] && AUTOMATED_MODE=true
    [[ "${NVIDIA_TOOLKIT_FORCE}" == "true" ]] && FORCE_INSTALL=true
    [[ "${NVIDIA_TOOLKIT_QUIET}" == "true" ]] && QUIET_MODE=true
    [[ "${NVIDIA_TOOLKIT_EXPERIMENTAL}" == "true" ]] && INSTALL_EXPERIMENTAL=true
    [[ "${NVIDIA_TOOLKIT_CHINA_MIRROR}" == "true" ]] && USE_CHINA_MIRROR=true
    [[ -n "${NVIDIA_TOOLKIT_VERSION}" ]] && CUSTOM_VERSION="${NVIDIA_TOOLKIT_VERSION}"

    # 根据本地系统配置建议使用中国镜像（仅在自动化模式下）
    if [[ "$USE_CHINA_MIRROR" != "true" ]] && [[ "$AUTOMATED_MODE" == "true" ]] && detect_china_region; then
        USE_CHINA_MIRROR=true
        log_info "基于系统配置检测到中文环境，自动启用镜像加速"
    fi

    # 配置镜像地址
    if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
        NVIDIA_REPO_BASE="$CHINA_NVIDIA_REPO_BASE"
        DOCKER_REGISTRY="$CHINA_DOCKER_REGISTRY/"
        log_info "使用中国镜像加速"
    fi
}

# 检测是否需要使用中国镜像（基于本地配置）
detect_china_region() {
    # 仅基于本地系统配置检测，不涉及网络请求

    # 检测时区
    if [[ -f /etc/timezone ]] && grep -q "Shanghai\|Chongqing" /etc/timezone; then
        return 0
    fi

    # 检测系统语言环境
    if [[ "$LANG" =~ zh_CN ]] || [[ "$LC_ALL" =~ zh_CN ]]; then
        return 0
    fi

    # 检测系统时区设置
    if [[ -L /etc/localtime ]] && readlink /etc/localtime | grep -q "Shanghai\|Chongqing"; then
        return 0
    fi

    # 通过 timedatectl 检测时区（如果可用）
    if command -v timedatectl &>/dev/null; then
        if timedatectl 2>/dev/null | grep -q "Asia/Shanghai\|Asia/Chongqing"; then
            return 0
        fi
    fi

    return 1
}

# 日志函数
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

log_info() {
    local msg="$1"
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $msg"
    fi
    log_to_file "INFO: $msg"
}

log_success() {
    local msg="$1"
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $msg"
    fi
    log_to_file "SUCCESS: $msg"
}

log_warning() {
    local msg="$1"
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} $msg"
    fi
    log_to_file "WARNING: $msg"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $msg" >&2
    log_to_file "ERROR: $msg"
}

log_debug() {
    local msg="$1"
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $msg"
    fi
    log_to_file "DEBUG: $msg"
}

# 锁文件管理
acquire_lock() {
    log_info "尝试获取安装锁..."

    # 检查是否存在锁文件
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)

        # 检查锁文件中的进程是否仍在运行
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_error "另一个安装进程正在运行 (PID: $lock_pid)"
            log_info "如果确认没有其他安装进程在运行，可以删除锁文件: rm $LOCK_FILE"
            exit 1
        else
            log_warning "发现过期的锁文件，正在清理..."
            rm -f "$LOCK_FILE"
        fi
    fi

    # 创建锁文件
    echo "$PID" >"$LOCK_FILE"
    if [[ $? -ne 0 ]]; then
        log_error "无法创建锁文件: $LOCK_FILE"
        exit 1
    fi

    log_success "获取安装锁成功 (PID: $PID)"
}

release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ "$lock_pid" == "$PID" ]]; then
            rm -f "$LOCK_FILE"
            log_info "释放安装锁"
        fi
    fi
}

# 状态管理
save_state() {
    local step="$1"
    local status="$2"
    echo "STEP=$step" >"$STATE_FILE"
    echo "STATUS=$status" >>"$STATE_FILE"
    echo "TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')" >>"$STATE_FILE"
    echo "PID=$PID" >>"$STATE_FILE"
    log_debug "保存状态: $step - $status"
}

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE" 2>/dev/null
        return 0
    fi
    return 1
}

clear_state() {
    rm -f "$STATE_FILE"
    log_debug "清除状态文件"
}

# 检查步骤是否已完成
is_step_completed() {
    local step="$1"
    if load_state; then
        [[ "$STEP" == "$step" && "$STATUS" == "completed" ]]
    else
        return 1
    fi
}

# 检查是否可以跳过某个步骤
should_skip_step() {
    local step="$1"

    case "$step" in
    "repo_config")
        # 检查仓库配置是否已存在
        case $PACKAGE_MANAGER in
        apt)
            [[ -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]]
            ;;
        dnf | yum)
            [[ -f /etc/yum.repos.d/nvidia-container-toolkit.repo ]]
            ;;
        zypper)
            sudo zypper lr 2>/dev/null | grep -q nvidia-container-toolkit
            ;;
        *)
            return 1
            ;;
        esac
        ;;
    "package_install")
        # 检查 nvidia-ctk 是否已安装
        command -v nvidia-ctk &>/dev/null
        ;;
    "docker_config")
        # 检查 Docker 配置是否已存在
        [[ -f /etc/docker/daemon.json ]] && grep -q "nvidia" /etc/docker/daemon.json
        ;;
    *)
        return 1
        ;;
    esac
}

# 幂等性检查和恢复
check_and_resume() {
    log_info "检查之前的安装状态..."

    if load_state; then
        log_info "发现之前的安装记录: $STEP ($STATUS) - $TIMESTAMP"

        if [[ "$STATUS" == "completed" ]]; then
            log_success "步骤 '$STEP' 已完成"
            return 0
        elif [[ "$STATUS" == "in_progress" ]]; then
            log_warning "步骤 '$STEP' 上次未完成，将重新执行"
            return 1
        fi
    else
        log_info "未发现之前的安装记录，开始全新安装"
        return 0
    fi
}

auto_confirm() {
    local message="$1"
    local default_yes="$2" # true 为默认 yes

    if [[ "$AUTOMATED_MODE" == "true" ]]; then
        if [[ "$default_yes" == "true" ]]; then
            log_info "$message [自动确认: YES]"
            return 0
        else
            log_info "$message [自动确认: NO]"
            return 1
        fi
    else
        read -p "$message (y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# 检查是否以 root 权限运行
check_root() {
    # 检查 sudo 权限
    if ! sudo -v 2>/dev/null; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            log_warning "无法获取 sudo 权限，但启用了强制模式，继续执行"
        else
            log_error "需要 sudo 权限来安装软件包"
            exit 1
        fi
    fi
}

# 检查网络连接
check_network() {
    log_info "检查网络连接..."

    local test_url="$NVIDIA_REPO_BASE/"

    if ! curl -fsSL --connect-timeout 10 --max-time 20 "$test_url" >/dev/null; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            log_warning "网络连接检查失败，但启用了强制模式，继续执行"
        else
            log_error "无法连接到 NVIDIA 仓库: $test_url"
            log_info "请检查网络连接，或尝试使用 --china-mirror 选项"
            exit 1
        fi
    else
        log_success "网络连接正常"
    fi
}

# 检查系统要求
check_requirements() {
    log_info "检查系统要求..."

    # 检查 NVIDIA 驱动
    if ! command -v nvidia-smi &>/dev/null; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            log_warning "未检测到 NVIDIA 驱动，但启用了强制模式，继续执行"
        else
            log_error "未检测到 NVIDIA 驱动，请先安装 NVIDIA 驱动"
            log_info "您可使用我们的 NVIDIA 驱动一键安装脚本进行安装:"
            log_info "   $ curl -sSL https://raw.githubusercontent.com/EM-GeekLab/nvidia-driver-installer/main/nvidia-install.sh -o nvidia-install.sh"
            log_info "   $ sudo bash nvidia-install.sh"

            if [[ "$AUTOMATED_MODE" != "true" ]]; then
                if auto_confirm "是否要继续安装（可能会失败）？" false; then
                    log_warning "用户选择继续安装，可能会遇到问题"
                else
                    exit 1
                fi
            else
                exit 1
            fi
        fi
    else
        log_success "NVIDIA 驱动已安装"
        log_debug "NVIDIA 驱动版本: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)"
    fi

    # 检查 Docker
    if ! command -v docker &>/dev/null; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            log_warning "未检测到 Docker，但启用了强制模式，继续执行"
        else
            log_error "未检测到 Docker，请先安装 Docker"
            log_info "请参考: https://docs.docker.com/engine/install/"

            if [[ "$AUTOMATED_MODE" != "true" ]]; then
                if auto_confirm "是否要继续安装（可能会失败）？" false; then
                    log_warning "用户选择继续安装，可能会遇到问题"
                else
                    exit 1
                fi
            else
                exit 1
            fi
        fi
    else
        log_success "Docker 已安装"

        # 检查 Docker 版本
        DOCKER_VERSION=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$DOCKER_VERSION" ]]; then
            DOCKER_MAJOR=$(echo $DOCKER_VERSION | cut -d. -f1)
            DOCKER_MINOR=$(echo $DOCKER_VERSION | cut -d. -f2)

            if [[ $DOCKER_MAJOR -lt 19 ]] || ([[ $DOCKER_MAJOR -eq 19 ]] && [[ $DOCKER_MINOR -lt 3 ]]); then
                log_warning "Docker 版本 $DOCKER_VERSION 可能不完全兼容，推荐版本 >= 19.03"
            else
                log_debug "Docker 版本: $DOCKER_VERSION (兼容)"
            fi
        fi
    fi

    # 检查用户是否在 docker 组中
    if [[ "$SKIP_DOCKER_USER_GROUP" != "true" ]] && ! groups $USER 2>/dev/null | grep -q docker; then
        if [[ "$AUTOMATED_MODE" == "true" ]]; then
            log_info "将用户 $USER 添加到 docker 组"
            sudo usermod -aG docker $USER
            log_success "用户已添加到 docker 组（需要重新登录生效）"
        else
            if auto_confirm "当前用户不在 docker 组中，是否添加？" true; then
                sudo usermod -aG docker $USER
                log_success "用户已添加到 docker 组（需要重新登录生效）"
            fi
        fi
    fi

    log_success "系统要求检查完成"
}

# 检测操作系统
detect_os() {
    log_info "检测操作系统..."

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID=$ID
        OS_VERSION_ID=$VERSION_ID
        OS_PRETTY_NAME=$PRETTY_NAME
    else
        log_error "无法检测操作系统版本"
        exit 1
    fi

    case $OS_ID in
    ubuntu | debian)
        PACKAGE_MANAGER="apt"
        ;;
    rhel | centos | fedora | rocky | almalinux)
        PACKAGE_MANAGER="dnf"
        # RHEL/CentOS 7 使用 yum
        if [[ $OS_ID == "centos" ]] || [[ $OS_ID == "rhel" ]]; then
            if [[ $OS_VERSION_ID == "7"* ]]; then
                PACKAGE_MANAGER="yum"
            fi
        fi
        ;;
    amzn)
        PACKAGE_MANAGER="yum"
        ;;
    opensuse* | sled | sles)
        PACKAGE_MANAGER="zypper"
        ;;
    arch)
        PACKAGE_MANAGER="pacman"
        log_warning "Arch Linux 支持有限，建议使用 AUR 包"
        ;;
    *)
        log_error "不支持的操作系统: $OS_ID"
        log_info "支持的系统: Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux, Amazon Linux, OpenSUSE, SLES"
        exit 1
        ;;
    esac

    log_success "检测到系统: $OS_PRETTY_NAME"
    log_debug "包管理器: $PACKAGE_MANAGER"
}

# 更新包管理器缓存
update_package_cache() {
    log_info "更新包管理器缓存..."
    save_state "cache_update" "in_progress"

    case $PACKAGE_MANAGER in
    apt)
        if [[ "$QUIET_MODE" == "true" ]]; then
            sudo apt-get update -qq
        else
            sudo apt-get update
        fi
        ;;
    dnf)
        if [[ "$QUIET_MODE" == "true" ]]; then
            sudo dnf makecache -q
        else
            sudo dnf makecache
        fi
        ;;
    yum)
        if [[ "$QUIET_MODE" == "true" ]]; then
            sudo yum makecache -q
        else
            sudo yum makecache
        fi
        ;;
    zypper)
        sudo zypper --non-interactive refresh
        ;;
    *)
        log_warning "不支持的包管理器: $PACKAGE_MANAGER"
        return 1
        ;;
    esac

    save_state "cache_update" "completed"
    log_success "包管理器缓存更新完成"
    return 0
}

# 确定安装版本（仓库配置后调用）
determine_version() {
    if [[ -n "$CUSTOM_VERSION" ]]; then
        NVIDIA_CONTAINER_TOOLKIT_VERSION="$CUSTOM_VERSION"
        log_info "使用指定版本: $NVIDIA_CONTAINER_TOOLKIT_VERSION"
        return 0
    fi

    # 尝试获取最新版本，如果失败则使用默认版本
    log_info "获取最新版本信息..."
    local latest_version=""

    # 尝试从不同源获取最新版本信息
    case $PACKAGE_MANAGER in
    apt)
        latest_version=$(get_latest_version_apt)
        ;;
    dnf | yum)
        latest_version=$(get_latest_version_rpm)
        ;;
    zypper)
        latest_version=$(get_latest_version_rpm)
        ;;
    *)
        log_warning "不支持的包管理器: $PACKAGE_MANAGER"
        ;;
    esac

    if [[ -n "$latest_version" && "$latest_version" != "1.17.8-1" ]]; then
        NVIDIA_CONTAINER_TOOLKIT_VERSION="$latest_version"
        log_info "使用最新版本: $NVIDIA_CONTAINER_TOOLKIT_VERSION"
    else
        # 如果无法获取最新版本，使用已知的稳定版本
        NVIDIA_CONTAINER_TOOLKIT_VERSION="1.17.8-1"
        if [[ -z "$latest_version" ]]; then
            log_warning "无法获取最新版本信息，使用默认版本: $NVIDIA_CONTAINER_TOOLKIT_VERSION"
        else
            log_info "使用默认版本: $NVIDIA_CONTAINER_TOOLKIT_VERSION"
        fi
    fi
}

# 预设版本（仓库配置前调用）
preset_version() {
    if [[ -n "$CUSTOM_VERSION" ]]; then
        NVIDIA_CONTAINER_TOOLKIT_VERSION="$CUSTOM_VERSION"
        log_info "预设指定版本: $NVIDIA_CONTAINER_TOOLKIT_VERSION"
    else
        # 预设默认版本，稍后在仓库配置后尝试获取最新版本
        NVIDIA_CONTAINER_TOOLKIT_VERSION="1.17.8-1"
        log_info "预设默认版本: $NVIDIA_CONTAINER_TOOLKIT_VERSION (稍后尝试获取最新版本)"
    fi
}

# 获取最新版本 - APT 系统
get_latest_version_apt() {
    local latest_version=""

    # 确保仓库已配置
    if [[ ! -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]]; then
        return 1
    fi

    # 更新包列表（静默模式）
    if ! sudo apt-get update -qq 2>/dev/null; then
        return 1
    fi

    # 获取可用版本
    latest_version=$(apt-cache policy nvidia-container-toolkit 2>/dev/null |
        grep "Candidate:" |
        awk '{print $2}' |
        head -1)

    if [[ -n "$latest_version" && "$latest_version" != "(none)" ]]; then
        echo "$latest_version"
        return 0
    fi

    return 1
}

# 获取最新版本 - RPM 系统
get_latest_version_rpm() {
    local latest_version=""

    # 根据包管理器选择命令
    local query_cmd=""
    if command -v dnf &>/dev/null; then
        query_cmd="dnf list available nvidia-container-toolkit 2>/dev/null"
    elif command -v yum &>/dev/null; then
        query_cmd="yum list available nvidia-container-toolkit 2>/dev/null"
    elif command -v zypper &>/dev/null; then
        query_cmd="zypper se -s nvidia-container-toolkit 2>/dev/null"
        # Zypper 的输出格式不同，需要特殊处理
        latest_version=$(eval $query_cmd |
            grep "nvidia-container-toolkit" |
            awk '{print $4}' |
            sort -V |
            tail -1)
        if [[ -n "$latest_version" ]]; then
            echo "$latest_version"
            return 0
        fi
        return 1
    else
        return 1
    fi

    # 解析 DNF/YUM 输出
    latest_version=$(eval $query_cmd |
        grep "nvidia-container-toolkit" |
        awk '{print $2}' |
        head -1)

    if [[ -n "$latest_version" ]]; then
        echo "$latest_version"
        return 0
    fi

    return 1
}

# 配置 NVIDIA 仓库 - APT 系统
configure_apt_repo() {
    log_info "配置 NVIDIA Container Toolkit APT 仓库..."
    save_state "repo_config_apt" "in_progress"

    # 检查是否已存在仓库配置且不是强制安装模式
    if [[ -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]] && [[ "$FORCE_INSTALL" != "true" ]]; then
        log_info "NVIDIA 仓库已存在，跳过配置"
        save_state "repo_config_apt" "completed"
        return 0
    fi

    # 添加 GPG 密钥
    local gpg_key_url="$NVIDIA_REPO_BASE/gpgkey"
    if ! curl -fsSL --connect-timeout 30 --max-time 60 "$gpg_key_url" |
        sudo gpg --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg; then
        log_error "添加 GPG 密钥失败: $gpg_key_url"
        return 1
    fi

    # 下载并修改仓库列表
    local repo_list_url="$NVIDIA_REPO_BASE/stable/deb/nvidia-container-toolkit.list"
    local temp_list="/tmp/nvidia-container-toolkit.list"
    if ! curl -fsSL --connect-timeout 30 --max-time 60 "$repo_list_url" -o "$temp_list"; then
        log_error "下载仓库列表失败: $repo_list_url"
        return 1
    fi

    # 验证下载的文件不为空且包含预期内容
    if [[ ! -s "$temp_list" ]] || ! grep -q "libnvidia-container" "$temp_list"; then
        log_error "下载的仓库列表文件无效或为空"
        rm -f "$temp_list"
        return 1
    fi

    # 替换域名并添加签名密钥
    if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
        sed -i "s#deb https://nvidia.github.io#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://mirrors.cloud.tencent.com#g" "$temp_list"
    else
        sed -i 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' "$temp_list"
    fi

    # 安装仓库列表
    sudo cp "$temp_list" /etc/apt/sources.list.d/nvidia-container-toolkit.list
    rm -f "$temp_list"

    # 如果需要实验版本
    if [[ "$INSTALL_EXPERIMENTAL" == "true" ]]; then
        log_info "启用实验版本仓库"
        sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list
    fi

    save_state "repo_config_apt" "completed"
    log_success "APT 仓库配置完成"
    return 0
}

# 配置 NVIDIA 仓库 - DNF/YUM 系统
configure_dnf_repo() {
    log_info "配置 NVIDIA Container Toolkit DNF/YUM 仓库..."
    save_state "repo_config_rpm" "in_progress"

    # 检查是否已存在仓库配置
    if [[ -f /etc/yum.repos.d/nvidia-container-toolkit.repo ]] && [[ "$FORCE_INSTALL" != "true" ]]; then
        log_info "NVIDIA 仓库已存在，跳过配置"
        save_state "repo_config_rpm" "completed"
        return 0
    fi

    # 下载仓库配置文件
    local repo_url="$NVIDIA_REPO_BASE/stable/rpm/nvidia-container-toolkit.repo"
    local temp_repo="/tmp/nvidia-container-toolkit.repo"

    if ! curl -fsSL --connect-timeout 30 --max-time 60 "$repo_url" -o "$temp_repo"; then
        log_error "下载仓库配置失败: $repo_url"
        return 1
    fi

    # 验证下载的文件不为空且包含预期内容
    if [[ ! -s "$temp_repo" ]] || ! grep -q "nvidia-container-toolkit" "$temp_repo"; then
        log_error "下载的仓库配置文件无效或为空"
        rm -f "$temp_repo"
        return 1
    fi

    # 如果使用中国镜像，替换域名
    if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
        sed -i 's#https://nvidia.github.io/libnvidia-container#https://mirrors.cloud.tencent.com/libnvidia-container#g' "$temp_repo"
    fi

    # 安装仓库配置
    sudo cp "$temp_repo" /etc/yum.repos.d/nvidia-container-toolkit.repo
    rm -f "$temp_repo"

    # 如果需要实验版本
    if [[ "$INSTALL_EXPERIMENTAL" == "true" ]]; then
        log_info "启用实验版本仓库"
        if command -v dnf &>/dev/null; then
            sudo dnf config-manager --enable nvidia-container-toolkit-experimental
        else
            # 对于 yum，手动编辑配置文件
            sudo sed -i '/\[nvidia-container-toolkit-experimental\]/,/^\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/nvidia-container-toolkit.repo
        fi
    fi

    save_state "repo_config_rpm" "completed"
    log_success "DNF/YUM 仓库配置完成"
    return 0
}

# 配置 NVIDIA 仓库 - Zypper 系统
configure_zypper_repo() {
    log_info "配置 NVIDIA Container Toolkit Zypper 仓库..."
    save_state "repo_config_zypper" "in_progress"

    # 检查是否已存在仓库
    if sudo zypper lr 2>/dev/null | grep -q nvidia-container-toolkit && [[ "$FORCE_INSTALL" != "true" ]]; then
        log_info "NVIDIA 仓库已存在，跳过配置"
        save_state "repo_config_zypper" "completed"
        return 0
    fi

    local repo_url="$NVIDIA_REPO_BASE/stable/rpm/nvidia-container-toolkit.repo"

    # 如果使用中国镜像，需要下载并修改仓库文件
    if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
        local temp_repo="/tmp/nvidia-container-toolkit.repo"

        if ! curl -fsSL --connect-timeout 30 --max-time 60 "$repo_url" -o "$temp_repo"; then
            log_error "下载仓库配置失败: $repo_url"
            return 1
        fi

        # 验证下载的文件
        if [[ ! -s "$temp_repo" ]] || ! grep -q "nvidia-container-toolkit" "$temp_repo"; then
            log_error "下载的仓库配置文件无效或为空"
            rm -f "$temp_repo"
            return 1
        fi

        # 替换域名
        sed -i 's#https://nvidia.github.io/libnvidia-container#https://mirrors.cloud.tencent.com/libnvidia-container#g' "$temp_repo"

        # 添加修改后的仓库
        if ! sudo zypper --non-interactive ar "$temp_repo"; then
            log_error "添加仓库失败"
            rm -f "$temp_repo"
            return 1
        fi

        rm -f "$temp_repo"
    else
        if ! sudo zypper --non-interactive ar "$repo_url"; then
            log_error "添加仓库失败"
            return 1
        fi
    fi
    # 如果需要实验版本
    if [[ "$INSTALL_EXPERIMENTAL" == "true" ]]; then
        log_info "启用实验版本仓库"
        sudo zypper modifyrepo --enable nvidia-container-toolkit-experimental
    fi

    save_state "repo_config_zypper" "completed"
    log_success "Zypper 仓库配置完成"
    return 0
}

# 安装 NVIDIA Container Toolkit - APT
install_with_apt() {
    log_info "使用 APT 安装 NVIDIA Container Toolkit..."
    save_state "package_install_apt" "in_progress"

    local install_cmd="sudo apt-get install -y"

    if [[ "$QUIET_MODE" == "true" ]]; then
        install_cmd+=" -qq"
    fi

    # 如果版本号不包含 "=" 符号，说明可能是从仓库获取的完整版本，直接使用
    # 否则构建完整的包名=版本格式
    local packages=()
    if [[ "$NVIDIA_CONTAINER_TOOLKIT_VERSION" == *"="* ]]; then
        # 版本号已包含包名，直接使用
        packages=("$NVIDIA_CONTAINER_TOOLKIT_VERSION")
    else
        # 构建包列表
        packages=(
            "nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
            "nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
            "libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
            "libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        )
    fi

    # 尝试安装，如果指定版本失败，则尝试安装最新版本
    if ! $install_cmd "${packages[@]}"; then
        if [[ -n "$CUSTOM_VERSION" ]]; then
            log_error "指定版本 $CUSTOM_VERSION 安装失败"
            return 1
        else
            log_warning "指定版本安装失败，尝试安装最新版本"
            if ! $install_cmd nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1; then
                log_error "APT 安装失败"
                return 1
            fi
        fi
    fi

    save_state "package_install_apt" "completed"
    log_success "APT 安装完成"
    return 0
}

# 安装 NVIDIA Container Toolkit - DNF
install_with_dnf() {
    log_info "使用 DNF 安装 NVIDIA Container Toolkit..."
    save_state "package_install_dnf" "in_progress"

    local install_cmd="sudo dnf install -y"

    if [[ "$QUIET_MODE" == "true" ]]; then
        install_cmd+=" -q"
    fi

    # 构建包列表
    local packages=(
        "nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
    )

    # 尝试安装，如果指定版本失败，则尝试安装最新版本
    if ! $install_cmd "${packages[@]}"; then
        if [[ -n "$CUSTOM_VERSION" ]]; then
            log_error "指定版本 $CUSTOM_VERSION 安装失败"
            return 1
        else
            log_warning "指定版本安装失败，尝试安装最新版本"
            if ! $install_cmd nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1; then
                log_error "DNF 安装失败"
                return 1
            fi
        fi
    fi

    save_state "package_install_dnf" "completed"
    log_success "DNF 安装完成"
    return 0
}

# 安装 NVIDIA Container Toolkit - YUM
install_with_yum() {
    log_info "使用 YUM 安装 NVIDIA Container Toolkit..."
    save_state "package_install_yum" "in_progress"

    local install_cmd="sudo yum install -y"

    if [[ "$QUIET_MODE" == "true" ]]; then
        install_cmd+=" -q"
    fi

    # 构建包列表
    local packages=(
        "nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
    )

    # 尝试安装，如果指定版本失败，则尝试安装最新版本
    if ! $install_cmd "${packages[@]}"; then
        if [[ -n "$CUSTOM_VERSION" ]]; then
            log_error "指定版本 $CUSTOM_VERSION 安装失败"
            return 1
        else
            log_warning "指定版本安装失败，尝试安装最新版本"
            if ! $install_cmd nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1; then
                log_error "YUM 安装失败"
                return 1
            fi
        fi
    fi

    save_state "package_install_yum" "completed"
    log_success "YUM 安装完成"
    return 0
}

# 安装 NVIDIA Container Toolkit - Zypper
install_with_zypper() {
    log_info "使用 Zypper 安装 NVIDIA Container Toolkit..."
    save_state "package_install_zypper" "in_progress"

    local install_cmd="sudo zypper --non-interactive --gpg-auto-import-keys install -y"

    # 构建包列表
    local packages=(
        "nvidia-container-toolkit-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "nvidia-container-toolkit-base-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "libnvidia-container-tools-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
        "libnvidia-container1-${NVIDIA_CONTAINER_TOOLKIT_VERSION}"
    )

    # 尝试安装，如果指定版本失败，则尝试安装最新版本
    if ! $install_cmd "${packages[@]}"; then
        if [[ -n "$CUSTOM_VERSION" ]]; then
            log_error "指定版本 $CUSTOM_VERSION 安装失败"
            return 1
        else
            log_warning "指定版本安装失败，尝试安装最新版本"
            if ! $install_cmd nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1; then
                log_error "Zypper 安装失败"
                return 1
            fi
        fi
    fi

    save_state "package_install_zypper" "completed"
    log_success "Zypper 安装完成"
    return 0
}

# 配置 Docker 运行时
configure_docker() {
    log_info "配置 Docker 运行时..."
    save_state "docker_config" "in_progress"

    # 使用 nvidia-ctk 命令配置 Docker
    if ! sudo nvidia-ctk runtime configure --runtime=docker; then
        log_error "配置 Docker 运行时失败"
        return 1
    fi

    # 重启 Docker 服务
    if ! sudo systemctl restart docker; then
        if [[ "$FORCE_INSTALL" == "true" ]]; then
            log_warning "Docker 服务重启失败，但启用了强制模式，继续执行"
        else
            log_error "Docker 服务重启失败"
            return 1
        fi
    else
        log_success "Docker 服务重启成功"
    fi

    # 等待 Docker 服务完全启动
    sleep 3

    save_state "docker_config" "completed"
    log_success "Docker 运行时配置完成"
    return 0
}

# 基础验证（不拉取镜像）
verify_installation_basic() {
    log_info "执行基础验证..."

    # 检查 nvidia-ctk 命令
    if ! command -v nvidia-ctk &>/dev/null; then
        log_error "nvidia-ctk 命令未找到，安装可能失败"
        return 1
    fi

    # 显示版本信息
    local version_info=$(nvidia-ctk --version 2>/dev/null || echo "无法获取版本信息")
    log_info "NVIDIA Container Toolkit 版本: $version_info"

    # 检查配置文件
    if [[ -f /etc/docker/daemon.json ]]; then
        if grep -q "nvidia" /etc/docker/daemon.json; then
            log_success "Docker 配置文件已正确更新"
        else
            log_warning "Docker 配置文件可能未正确配置"
        fi
    fi

    log_success "基础验证完成"
    return 0
}

# Docker GPU 访问验证（独立函数，可单独调用）
verify_docker_gpu_access() {
    log_info "=========================================="
    log_info "独立 Docker GPU 访问验证"
    log_info "=========================================="

    # 检查 Docker 是否运行
    if ! docker info &>/dev/null; then
        log_error "Docker 服务未运行，请先启动 Docker 服务"
        log_info "sudo systemctl start docker"
        return 1
    fi

    # 检查 nvidia-smi 是否可用
    if ! command -v nvidia-smi &>/dev/null; then
        log_error "nvidia-smi 命令未找到，请先安装 NVIDIA 驱动"
        return 1
    fi

    # 检查 nvidia-ctk 是否可用
    if ! command -v nvidia-ctk &>/dev/null; then
        log_error "nvidia-ctk 命令未找到，请先安装 NVIDIA Container Toolkit"
        return 1
    fi

    log_info "开始 Docker GPU 访问测试..."

    # 选择测试镜像
    local test_image="ubuntu:20.04"
    if [[ -n "$DOCKER_REGISTRY" ]]; then
        test_image="${DOCKER_REGISTRY}${test_image}"
    fi

    log_info "使用测试镜像: $test_image"

    # 预先拉取镜像以避免测试时的网络延迟
    log_info "拉取测试镜像..."
    if ! timeout 300 docker pull "$test_image"; then
        log_error "拉取测试镜像失败"
        log_info "您可以手动拉取镜像: docker pull $test_image"
        return 1
    fi

    # 测试1: 基础 GPU 访问测试
    log_info "测试 1/3: 基础 GPU 访问测试..."
    local test_cmd="timeout 60 docker run --rm --runtime=nvidia --gpus all $test_image nvidia-smi"

    log_debug "执行命令: $test_cmd"

    if $test_cmd >/tmp/gpu_test_1.log 2>&1; then
        log_success "✓ 基础 GPU 访问测试成功"
        log_info "检测到的 GPU:"
        grep -E "GPU|GeForce|Quadro|Tesla" /tmp/gpu_test_1.log | head -3 || log_info "GPU 信息解析失败"
    else
        log_error "✗ 基础 GPU 访问测试失败"
        log_info "错误日志:"
        cat /tmp/gpu_test_1.log
        return 1
    fi

    # 测试2: 使用新的 --gpus 语法
    log_info "测试 2/3: 新 GPU 语法测试..."
    test_cmd="timeout 60 docker run --rm --gpus all $test_image nvidia-smi -L"

    log_debug "执行命令: $test_cmd"

    if $test_cmd >/tmp/gpu_test_2.log 2>&1; then
        log_success "✓ 新 GPU 语法测试成功"
        local gpu_count=$(grep -c "GPU" /tmp/gpu_test_2.log || echo "0")
        log_info "检测到 $gpu_count 个 GPU 设备"
    else
        log_error "✗ 新 GPU 语法测试失败"
        log_info "错误日志:"
        cat /tmp/gpu_test_2.log
        return 1
    fi

    # 测试3: 指定单个 GPU 测试
    log_info "测试 3/3: 单 GPU 访问测试..."
    test_cmd="timeout 60 docker run --rm --gpus device=0 $test_image nvidia-smi -i 0"

    log_debug "执行命令: $test_cmd"

    if $test_cmd >/tmp/gpu_test_3.log 2>&1; then
        log_success "✓ 单 GPU 访问测试成功"
    else
        log_warning "✗ 单 GPU 访问测试失败（这可能是正常的，如果系统只有一个GPU或GPU编号不是0）"
        log_debug "错误日志:"
        cat /tmp/gpu_test_3.log
    fi

    # 清理临时日志文件
    rm -f /tmp/gpu_test_*.log

    log_success "=========================================="
    log_success "Docker GPU 访问验证完成！"
    log_success "=========================================="

    # 显示使用示例
    log_info "GPU 容器使用示例:"
    echo "  # 使用所有 GPU:"
    echo "  docker run --rm --gpus all nvidia/cuda:11.8-runtime-ubuntu20.04 nvidia-smi"
    echo "  "
    echo "  # 使用特定 GPU:"
    echo "  docker run --rm --gpus device=0 nvidia/cuda:11.8-runtime-ubuntu20.04 nvidia-smi"
    echo "  "
    echo "  # 限制 GPU 数量:"
    echo "  docker run --rm --gpus 2 nvidia/cuda:11.8-runtime-ubuntu20.04 nvidia-smi"

    return 0
}

# 验证安装
verify_installation() {
    # 总是执行基础验证
    if ! verify_installation_basic; then
        return 1
    fi

    # 根据配置决定是否执行 Docker GPU 验证
    if [[ "$RUN_DOCKER_VERIFICATION" == "true" ]]; then
        log_info "执行 Docker GPU 访问验证..."
        if verify_docker_gpu_access; then
            log_success "完整验证成功！"
            return 0
        else
            log_error "Docker GPU 访问验证失败"
            return 1
        fi
    else
        log_info "跳过 Docker GPU 访问验证（可使用 --enable-verification 启用）"
        log_success "基础验证完成！"
        return 0
    fi
}

# 清理函数
cleanup() {
    local exit_code=$?

    # 释放锁文件
    release_lock

    if [[ $exit_code -ne 0 ]]; then
        log_error "安装过程中发生错误，退出码: $exit_code"
        log_info "详细日志请查看: $LOG_FILE"

        # 保存失败状态
        if load_state; then
            save_state "$STEP" "failed"
        fi

        if [[ "$QUIET_MODE" != "true" ]]; then
            echo
            log_info "故障排除建议:"
            echo "1. 检查网络连接是否正常"
            echo "2. 确认 NVIDIA 驱动已正确安装: nvidia-smi"
            echo "3. 确认 Docker 服务正在运行: sudo systemctl status docker"
            echo "4. 尝试使用 --force 选项强制安装"
            echo "5. 如果在中国大陆，尝试使用 --china-mirror 选项"
            echo
            echo "重新运行此脚本将从失败的步骤继续:"
            echo "$0 $(echo "$@" | grep -v -- "--verify-only")"
            echo
            echo "如需完整的 GPU 验证，运行:"
            echo "$0 --verify-only"
            echo
            echo "清理状态文件并重新开始:"
            echo "rm -f $STATE_FILE $LOCK_FILE"
        fi
    else
        # 成功完成，清理状态文件
        clear_state
        log_success "安装成功完成"
    fi

    exit $exit_code
}

# 显示安装摘要
show_installation_summary() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        log_success "安装完成摘要："
        echo "========================="
        log_info "操作系统: $OS_PRETTY_NAME"
        log_info "包管理器: $PACKAGE_MANAGER"
        log_info "安装版本: $NVIDIA_CONTAINER_TOOLKIT_VERSION"
        log_info "实验版本: $([ "$INSTALL_EXPERIMENTAL" == "true" ] && echo "是" || echo "否")"
        log_info "中国镜像: $([ "$USE_CHINA_MIRROR" == "true" ] && echo "是" || echo "否")"
        log_info "Docker验证: $([ "$RUN_DOCKER_VERIFICATION" == "true" ] && echo "已执行" || echo "已跳过")"
        log_info "日志文件: $LOG_FILE"
        echo "========================="
    fi
}

# 显示后续步骤
show_next_steps() {
    if [[ "$QUIET_MODE" == "true" ]]; then
        return 0
    fi

    log_success "NVIDIA Container Toolkit 安装完成！"
    echo

    # 根据是否执行了 Docker 验证给出不同建议
    if [[ "$RUN_DOCKER_VERIFICATION" != "true" ]]; then
        log_info "推荐的下一步操作："
        echo
        echo "1. 运行完整的 GPU 验证:"
        echo "   $0 --verify-only"
        echo
    fi

    log_info "后续使用步骤："

    if [[ "$SKIP_DOCKER_USER_GROUP" != "true" ]] && groups $USER | grep -q docker; then
        echo "✓ 用户已在 docker 组中"
    else
        echo "1. 如果需要非 root 用户使用 Docker："
        echo "   sudo usermod -aG docker \$USER"
        echo "   然后重新登录"
        echo
    fi

    echo "2. 测试 GPU 容器："
    local test_image="nvidia/cuda:11.8-base-ubuntu22.04"
    if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
        test_image="${DOCKER_REGISTRY}${test_image}"
    fi
    echo "   docker run --rm --gpus all $test_image nvidia-smi"
    echo
    echo "3. 在容器中使用特定 GPU："
    echo "   docker run --rm --gpus device=0 $test_image nvidia-smi"
    echo
    echo "4. 使用所有 GPU："
    echo "   docker run --rm --gpus all your-image:tag"
    echo

    if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
        log_info "由于使用了中国镜像加速，Docker Hub 镜像也会通过 ${DOCKER_REGISTRY} 加速"
    fi

    echo
    log_info "更多信息请参考: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/"
}

# 主函数
main() {
    # 设置信号处理
    trap cleanup EXIT INT TERM

    # 解析命令行参数
    parse_arguments "$@"

    # 获取安装锁
    acquire_lock

    # 创建日志文件
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "NVIDIA Container Toolkit 安装日志 - $(date)" >"$LOG_FILE"

    if [[ "$QUIET_MODE" != "true" ]]; then
        echo "======================================"
        echo "NVIDIA Container Toolkit 安装脚本 v2.1"
        if [[ "$AUTOMATED_MODE" == "true" ]]; then
            echo "模式: 全自动化安装"
        else
            echo "模式: 交互式安装"
        fi
        if [[ "$USE_CHINA_MIRROR" == "true" ]]; then
            echo "网络: 中国镜像加速"
        fi
        echo "======================================"
        echo
    fi

    log_info "安装开始 - $(date)"
    log_info "使用参数: $*"
    log_info "进程ID: $PID"

    # 检查和恢复之前的状态
    check_and_resume

    # 基础检查
    check_root
    check_network
    check_requirements
    detect_os

    # 预设版本（如果用户指定了版本，则使用指定版本；否则使用默认版本）
    preset_version

    # 配置仓库 (幂等性检查)
    case $PACKAGE_MANAGER in
    apt)
        if ! is_step_completed "repo_config_apt" && ! should_skip_step "repo_config"; then
            if ! configure_apt_repo; then
                log_error "APT 仓库配置失败"
                exit 1
            fi
        else
            log_info "跳过 APT 仓库配置 (已完成或已存在)"
            save_state "repo_config_apt" "completed"
        fi
        ;;
    dnf | yum)
        if ! is_step_completed "repo_config_rpm" && ! should_skip_step "repo_config"; then
            if ! configure_dnf_repo; then
                log_error "DNF/YUM 仓库配置失败"
                exit 1
            fi
        else
            log_info "跳过 DNF/YUM 仓库配置 (已完成或已存在)"
            save_state "repo_config_rpm" "completed"
        fi
        ;;
    zypper)
        if ! is_step_completed "repo_config_zypper" && ! should_skip_step "repo_config"; then
            if ! configure_zypper_repo; then
                log_error "Zypper 仓库配置失败"
                exit 1
            fi
        else
            log_info "跳过 Zypper 仓库配置 (已完成或已存在)"
            save_state "repo_config_zypper" "completed"
        fi
        ;;
    pacman)
        log_error "Arch Linux 请使用 AUR 安装: yay -S nvidia-container-toolkit"
        exit 1
        ;;
    esac

    # 更新包管理器缓存 (总是执行，确保最新)
    if ! is_step_completed "cache_update"; then
        if ! update_package_cache; then
            log_error "包管理器缓存更新失败"
            exit 1
        fi
    else
        log_info "强制更新包管理器缓存..."
        if ! update_package_cache; then
            log_warning "包管理器缓存更新失败，但继续执行"
        fi
    fi

    # 现在仓库和缓存都已配置，尝试获取最新版本
    if [[ -z "$CUSTOM_VERSION" ]]; then
        log_info "仓库已配置，重新确定最新版本..."
        determine_version
    fi

    # 安装软件包 (幂等性检查)
    local install_step=""
    case $PACKAGE_MANAGER in
    apt)
        install_step="package_install_apt"
        ;;
    dnf)
        install_step="package_install_dnf"
        ;;
    yum)
        install_step="package_install_yum"
        ;;
    zypper)
        install_step="package_install_zypper"
        ;;
    esac

    if ! is_step_completed "$install_step" && ! should_skip_step "package_install"; then
        case $PACKAGE_MANAGER in
        apt)
            if ! install_with_apt; then
                log_error "APT 包安装失败"
                exit 1
            fi
            ;;
        dnf)
            if ! install_with_dnf; then
                log_error "DNF 包安装失败"
                exit 1
            fi
            ;;
        yum)
            if ! install_with_yum; then
                log_error "YUM 包安装失败"
                exit 1
            fi
            ;;
        zypper)
            if ! install_with_zypper; then
                log_error "Zypper 包安装失败"
                exit 1
            fi
            ;;
        esac
    else
        log_info "跳过软件包安装 (已完成)"
        save_state "$install_step" "completed"
    fi

    # 配置 Docker (幂等性检查)
    if ! is_step_completed "docker_config" && ! should_skip_step "docker_config"; then
        if ! configure_docker; then
            log_error "Docker 配置失败"
            exit 1
        fi
    else
        log_info "跳过 Docker 配置 (已完成或已存在)"
        save_state "docker_config" "completed"
    fi

    # 验证安装
    save_state "verification" "in_progress"
    if verify_installation; then
        save_state "verification" "completed"
        save_state "installation" "completed"
        show_installation_summary
        show_next_steps
        log_info "安装成功完成 - $(date)"
        exit 0
    else
        save_state "verification" "failed"
        log_error "安装验证失败，请检查错误信息和日志文件: $LOG_FILE"
        exit 1
    fi
}

# 脚本入口
main "$@"
