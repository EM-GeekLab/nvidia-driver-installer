#!/bin/bash

# NVIDIA Container Toolkit 全自动化卸载脚本

# Author: PEScn @ EM-GeekLab
# Modified: 2025-08-07
# License: Apache License 2.0
# GitHub: https://github.com/EM-GeekLab/nvidia-driver-installer

set -e # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }


# 全局变量
PACKAGE_MANAGER=""
OS_ID=""

# 检测操作系统
detect_os() {
    log_info "检测操作系统..."
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID=$ID
    else
        log_error "无法检测操作系统版本"
        exit 1
    fi

    case $OS_ID in
        ubuntu|debian) PACKAGE_MANAGER="apt";;
        rhel|centos|fedora|rocky|almalinux)
            if command -v dnf &>/dev/null; then
                PACKAGE_MANAGER="dnf"
            else
                PACKAGE_MANAGER="yum"
            fi
            ;;
        amzn) PACKAGE_MANAGER="yum";;
        opensuse*|sled|sles) PACKAGE_MANAGER="zypper";;
        *)
            log_error "不支持的操作系统: $OS_ID"
            exit 1
            ;;
    esac
    log_success "检测到系统: $NAME, 包管理器: $PACKAGE_MANAGER"
}

# 1. 移除软件包
remove_packages() {
    log_info "开始移除 NVIDIA Container Toolkit 相关软件包..."
    local packages_to_remove="nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1"
    
    case $PACKAGE_MANAGER in
        apt)
            # 使用 purge 彻底删除，包括配置文件
            sudo apt-get purge -y $packages_to_remove
            sudo apt-get autoremove -y # 清理不再需要的依赖
            ;;
        dnf|yum)
            sudo $PACKAGE_MANAGER remove -y $packages_to_remove
            ;;
        zypper)
            sudo zypper remove -y $packages_to_remove
            ;;
    esac
    log_success "软件包移除完成。"
}

# 2. 清理 Docker 配置文件
cleanup_docker_config() {
    log_info "开始清理 Docker 配置文件..."
    local DOCKER_CONFIG="/etc/docker/daemon.json"

    if [[ ! -f "$DOCKER_CONFIG" ]]; then
        log_info "未找到 Docker 配置文件，无需清理。"
        return
    fi
    
    # 仅当文件中包含 nvidia 配置时才继续
    if ! grep -q '"nvidia"' "$DOCKER_CONFIG"; then
        log_info "Docker 配置文件中未发现 NVIDIA runtime，无需清理。"
        return
    fi

    log_info "发现 NVIDIA runtime 配置，正在处理..."
    # 创建备份，以防万一
    sudo cp "$DOCKER_CONFIG" "${DOCKER_CONFIG}.bak-$(date +%s)"
    log_success "已创建备份文件: ${DOCKER_CONFIG}.bak-..."

    # 使用 jq 是最安全的方式来修改 JSON 文件
    if ! command -v jq &> /dev/null; then
        log_error "需要 'jq' 命令来安全地修改 JSON 文件。请先安装 'jq'。"
        log_info "  - Ubuntu/Debian: sudo apt-get install jq"
        log_info "  - CentOS/RHEL:   sudo yum install jq"
        log_info "安装 jq 后请重新运行此脚本。或者，您可以手动编辑 '$DOCKER_CONFIG' 文件。"
        exit 1
    fi

    log_info "使用 'jq' 安全地移除 NVIDIA runtime 配置..."
    # 移除 nvidia runtime, 如果 runtimes 对象变空则移除它, 如果默认 runtime 是 nvidia 则移除它
    TEMP_JSON=$(sudo jq '
        del(.runtimes.nvidia) |
        (if .runtimes | length == 0 then del(.runtimes) else . end) |
        (if .["default-runtime"]? == "nvidia" then del(.["default-runtime"]) else . end)
    ' "$DOCKER_CONFIG")

    # 如果清理后文件内容为空对象 '{}'，则直接删除文件
    if [[ "$(echo "$TEMP_JSON" | tr -d '[:space:]')" == "{}" ]]; then
        log_info "配置文件在移除 NVIDIA 设置后为空，将直接删除该文件。"
        sudo rm "$DOCKER_CONFIG"
    else
        log_info "正在更新配置文件..."
        echo "$TEMP_JSON" | sudo tee "$DOCKER_CONFIG" > /dev/null
    fi

    log_info "重启 Docker 服务以应用更改..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    log_success "Docker 配置清理并重启完成。"
}

# 3. 移除仓库配置
remove_repo_files() {
    log_info "开始移除 NVIDIA 仓库配置文件..."
    case $PACKAGE_MANAGER in
        apt)
            sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
            sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            log_info "正在更新 apt 缓存..."
            sudo apt-get update -qq
            ;;
        dnf|yum)
            sudo rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo
            log_info "正在清理 ${PACKAGE_MANAGER} 缓存..."
            sudo $PACKAGE_MANAGER clean all >/dev/null 2>&1
            ;;
        zypper)
            # 尝试移除已知的仓库名
            sudo zypper --non-interactive removerepo nvidia-container-toolkit nvidia-container-toolkit-experimental >/dev/null 2>&1 || true
            sudo zypper --non-interactive refresh
            ;;
    esac
    log_success "仓库文件移除完成。"
}

# 4. 清理安装脚本生成的临时文件
cleanup_script_files() {
    log_info "开始清理安装脚本生成的临时文件..."
    rm -f /tmp/nvidia-toolkit-install.log \
          /tmp/nvidia-toolkit-install.lock \
          /tmp/nvidia-toolkit-install.state
    log_success "临时文件清理完成。"
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要以 root 权限运行，请使用 'sudo ./uninstall_nvidia_toolkit.sh'"
        exit 1
    fi
    
    echo "=========================================="
    echo "NVIDIA Container Toolkit 卸载程序"
    echo "=========================================="
    echo
    read -p "这将永久移除 NVIDIA Container Toolkit 及其配置。是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "操作已取消。"
        exit 0
    fi

    detect_os
    remove_packages
    cleanup_docker_config
    remove_repo_files
    cleanup_script_files

    echo
    log_success "卸载完成！系统已恢复到安装前的状态。"
    log_info "所有相关软件包、仓库和配置文件均已移除。"
}

main "$@"
