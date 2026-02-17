#!/bin/bash

# NVIDIA 驱动卸载脚本

# Author: PEScn @ EM-GeekLab
# Modified: 2026-02-17
# License: Apache-2.0
# GitHub: https://github.com/EM-GeekLab/nvidia-driver-installer
# Website: https://nvidia-install.online
# 支持 RHEL系、SUSE系、Debian系、Fedora、Amazon Linux、Azure Linux等发行版

set -e

# Color Definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_NO_ROOT=1
readonly EXIT_NO_NVIDIA_FOUND=2
readonly EXIT_USER_CANCELLED=3
readonly EXIT_UNINSTALL_FAILED=4
readonly EXIT_INVALID_ARGS=5

# 全局变量
DISTRO_ID=""
DISTRO_VERSION=""
ARCH=""
AUTO_YES=false
FORCE_UNINSTALL=false
KEEP_CONFIGS=false
CLEAN_ALL=false
REBOOT_AFTER=false

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 确认函数
confirm() {
    local prompt="$1"
    local default="${2:-N}"

    if [[ "$AUTO_YES" == "true" ]]; then
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

# 显示用法
show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -y, --yes               自动确认所有提示 (无交互模式)
    -f, --force             强制卸载，忽略错误
    -k, --keep-configs      保留配置文件
    -c, --clean-all         清理所有相关文件 (包括配置和缓存)
    --auto-reboot           卸载完成后自动重启

示例:
    # 交互式卸载
    $0
    
    # 自动卸载并重启
    $0 -y --auto-reboot
    
    # 强制清理所有文件
    $0 -y -c -f

注意: 此脚本需要root权限运行
EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -f|--force)
                FORCE_UNINSTALL=true
                shift
                ;;
            -k|--keep-configs)
                KEEP_CONFIGS=true
                shift
                ;;
            -c|--clean-all)
                CLEAN_ALL=true
                shift
                ;;
            --auto-reboot)
                REBOOT_AFTER=true
                shift
                ;;
            *)
                echo "未知选项: $1"
                show_usage
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行，请使用: sudo $0"
        exit $EXIT_NO_ROOT
    fi
}

# 检测操作系统
detect_distro() {
    log_step "检测操作系统..."
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO_ID=$ID
        DISTRO_VERSION=$VERSION_ID
        ARCH=$(uname -m)
        
        log_success "检测到: $NAME ($DISTRO_ID $DISTRO_VERSION) [$ARCH]"
    else
        log_error "无法检测操作系统"
        exit 1
    fi
}

# 检测NVIDIA安装
detect_nvidia_installation() {
    log_step "检测NVIDIA驱动安装..."
    
    local nvidia_found=false
    local installation_methods=()
    
    # 检查内核模块
    if lsmod | grep -q nvidia; then
        nvidia_found=true
        installation_methods+=("内核模块")
        log_info "检测到已加载的NVIDIA内核模块"
    fi
    
    # 检查包管理器安装
    case $DISTRO_ID in
        ubuntu|debian)
            if dpkg -l | grep -q nvidia; then
                nvidia_found=true
                installation_methods+=("APT包管理器")
                log_info "检测到通过APT安装的NVIDIA包"
            fi
            ;;
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            if rpm -qa | grep -q nvidia; then
                nvidia_found=true
                installation_methods+=("RPM包管理器")
                log_info "检测到通过RPM安装的NVIDIA包"
            fi
            ;;
        opensuse*|sles)
            if zypper search -i | grep -q nvidia; then
                nvidia_found=true
                installation_methods+=("Zypper包管理器")
                log_info "检测到通过Zypper安装的NVIDIA包"
            fi
            ;;
        azurelinux|mariner)
            if tdnf list installed | grep -q nvidia; then
                nvidia_found=true
                installation_methods+=("TDNF包管理器")
                log_info "检测到通过TDNF安装的NVIDIA包"
            fi
            ;;
    esac
    
    # 检查runfile安装
    if [[ -f /usr/bin/nvidia-uninstall ]]; then
        nvidia_found=true
        installation_methods+=("Runfile安装")
        log_info "检测到通过runfile安装的NVIDIA驱动"
    fi
    
    # 检查nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        nvidia_found=true
        log_info "检测到nvidia-smi工具"
    fi
    
    if [[ "$nvidia_found" == "false" ]]; then
        log_warning "未检测到NVIDIA驱动安装"
        if ! [[ "$FORCE_UNINSTALL" == "true" ]]; then
            exit $EXIT_NO_NVIDIA_FOUND
        fi
    else
        log_success "检测到NVIDIA驱动，安装方式: ${installation_methods[*]}"
    fi
}

# 显示将要卸载的组件
show_uninstall_plan() {
    log_step "卸载计划..."
    
    echo "将要卸载的组件:"
    echo "• NVIDIA驱动内核模块"
    echo "• NVIDIA用户空间库"
    echo "• NVIDIA管理工具 (nvidia-smi等)"
    
    if [[ "$CLEAN_ALL" == "true" ]]; then
        echo "• NVIDIA配置文件"
        echo "• NVIDIA缓存文件"
        echo "• NVIDIA日志文件"
        echo "• 第三方仓库配置"
    elif [[ "$KEEP_CONFIGS" == "false" ]]; then
        echo "• 基本配置文件"
    fi
    
    echo
    if ! [[ "$AUTO_YES" == "true" ]]; then
        if ! confirm "是否继续卸载？" "N"; then
            exit $EXIT_USER_CANCELLED
        fi
    fi
}

# 停止NVIDIA服务
stop_nvidia_services() {
    log_step "停止NVIDIA相关服务..."
    
    local services=("nvidia-persistenced" "nvidia-fabricmanager")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "停止服务: $service"
            systemctl stop "$service" || log_warning "无法停止 $service"
            systemctl disable "$service" 2>/dev/null || true
        fi
    done
}

# 停止使用GPU的进程
stop_gpu_processes() {
    log_step "检查并停止使用GPU的进程..."
    
    # 检查是否有进程在使用NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        local gpu_processes=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader,nounits 2>/dev/null || true)
        if [[ -n "$gpu_processes" ]]; then
            log_warning "检测到以下进程正在使用GPU:"
            nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null || true
            
            if [[ "$FORCE_UNINSTALL" == "true" ]] || confirm "是否强制终止这些进程？" "N"; then
                echo "$gpu_processes" | while read -r pid; do
                    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                        log_info "终止进程 PID: $pid"
                        kill -TERM "$pid" 2>/dev/null || true
                        sleep 2
                        if kill -0 "$pid" 2>/dev/null; then
                            kill -KILL "$pid" 2>/dev/null || true
                        fi
                    fi
                done
            fi
        fi
    fi
    
    # 停止显示管理器
    local display_managers=("gdm" "gdm3" "lightdm" "sddm" "xdm" "kdm")
    local stopped_dms=()
    
    for dm in "${display_managers[@]}"; do
        if systemctl is-active --quiet "$dm" 2>/dev/null; then
            log_info "停止显示管理器: $dm"
            if systemctl stop "$dm" 2>/dev/null; then
                stopped_dms+=("$dm")
            fi
        fi
    done
    
    if [[ ${#stopped_dms[@]} -gt 0 ]]; then
        log_info "已停止显示管理器: ${stopped_dms[*]}"
        echo "${stopped_dms[*]}" > /tmp/stopped_display_managers
    fi
}

# 卸载内核模块
unload_nvidia_modules() {
    log_step "卸载NVIDIA内核模块..."
    
    local modules=("nvidia_drm" "nvidia_modeset" "nvidia_uvm" "nvidia")
    local failed_modules=()
    
    for module in "${modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            log_info "卸载模块: $module"
            if modprobe -r "$module" 2>/dev/null; then
                log_success "成功卸载: $module"
            else
                log_warning "无法卸载: $module"
                failed_modules+=("$module")
            fi
        fi
    done
    
    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        log_warning "以下模块无法卸载，可能需要重启: ${failed_modules[*]}"
        return 1
    fi
    
    return 0
}

# 卸载包管理器安装的包
uninstall_packages() {
    log_step "卸载NVIDIA相关包..."
    
    case $DISTRO_ID in
        ubuntu|debian)
            local packages=$(dpkg -l | grep nvidia | awk '{print $2}' | tr '\n' ' ')
            if [[ -n "$packages" ]]; then
                log_info "卸载APT包: $packages"
                apt remove --purge -y $packages || [[ "$FORCE_UNINSTALL" == "true" ]]
                apt autoremove -y || true
            fi
            
            # 卸载CUDA相关包
            local cuda_packages=$(dpkg -l | grep cuda | awk '{print $2}' | tr '\n' ' ')
            if [[ -n "$cuda_packages" ]]; then
                log_info "卸载CUDA包: $cuda_packages"
                apt remove --purge -y $cuda_packages || [[ "$FORCE_UNINSTALL" == "true" ]]
            fi
            ;;
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            local packages=$(rpm -qa | grep nvidia | tr '\n' ' ')
            if [[ -n "$packages" ]]; then
                log_info "卸载RPM包: $packages"
                if command -v dnf &> /dev/null; then
                    dnf remove -y $packages || [[ "$FORCE_UNINSTALL" == "true" ]]
                    dnf autoremove -y || true
                else
                    yum remove -y $packages || [[ "$FORCE_UNINSTALL" == "true" ]]
                fi
            fi
            
            # 卸载CUDA相关包
            local cuda_packages=$(rpm -qa | grep cuda | tr '\n' ' ')
            if [[ -n "$cuda_packages" ]]; then
                log_info "卸载CUDA包: $cuda_packages"
                if command -v dnf &> /dev/null; then
                    dnf remove -y $cuda_packages || [[ "$FORCE_UNINSTALL" == "true" ]]
                else
                    yum remove -y $cuda_packages || [[ "$FORCE_UNINSTALL" == "true" ]]
                fi
            fi
            ;;
        opensuse*|sles)
            local packages=$(zypper search -i | grep nvidia | awk '{print $3}' | tr '\n' ' ')
            if [[ -n "$packages" ]]; then
                log_info "卸载Zypper包: $packages"
                zypper remove -y $packages || [[ "$FORCE_UNINSTALL" == "true" ]]
            fi
            ;;
        azurelinux|mariner)
            local packages=$(tdnf list installed | grep nvidia | awk '{print $1}' | tr '\n' ' ')
            if [[ -n "$packages" ]]; then
                log_info "卸载TDNF包: $packages"
                tdnf remove -y $packages || [[ "$FORCE_UNINSTALL" == "true" ]]
            fi
            ;;
    esac
}

# 卸载runfile安装
uninstall_runfile() {
    if [[ -f /usr/bin/nvidia-uninstall ]]; then
        log_step "执行runfile卸载..."
        /usr/bin/nvidia-uninstall --silent || [[ "$FORCE_UNINSTALL" == "true" ]]
    fi
}

# 清理配置文件
cleanup_configs() {
    if [[ "$KEEP_CONFIGS" == "true" ]]; then
        log_info "保留配置文件 (--keep-configs 已启用)"
        return 0
    fi
    
    log_step "清理配置文件..."
    
    local config_files=(
        "/etc/modprobe.d/*nvidia*"
        "/etc/modprobe.d/*nouveau*"
        "/etc/X11/xorg.conf.d/*nvidia*"
        "/etc/nvidia"
        "/usr/share/X11/xorg.conf.d/*nvidia*"
    )
    
    for pattern in "${config_files[@]}"; do
        if ls $pattern 2>/dev/null; then
            log_info "删除配置: $pattern"
            rm -rf $pattern
        fi
    done
    
    # 恢复nouveau
    if [[ -f /etc/modprobe.d/blacklist-nvidia-nouveau.conf ]]; then
        log_info "删除nouveau黑名单"
        rm -f /etc/modprobe.d/blacklist-nvidia-nouveau.conf
    fi
}

# 深度清理
deep_cleanup() {
    if [[ "$CLEAN_ALL" != "true" ]]; then
        return 0
    fi
    
    log_step "执行深度清理..."
    
    # 清理用户目录
    local user_dirs=()
    while IFS= read -r -d '' dir; do
        user_dirs+=("$dir")
    done < <(find /home -maxdepth 1 -type d -print0 2>/dev/null)
    
    for user_dir in "${user_dirs[@]}"; do
        local nvidia_cache="$user_dir/.nv"
        local cuda_cache="$user_dir/.cuda"
        if [[ -d "$nvidia_cache" ]]; then
            log_info "清理用户缓存: $nvidia_cache"
            rm -rf "$nvidia_cache"
        fi
        if [[ -d "$cuda_cache" ]]; then
            log_info "清理CUDA缓存: $cuda_cache"
            rm -rf "$cuda_cache"
        fi
    done
    
    # 清理系统缓存和日志
    local cleanup_paths=(
        "/var/log/nvidia*"
        "/var/lib/nvidia*"
        "/tmp/.nvidia*"
        "/tmp/.X*-lock"
        "/opt/nvidia"
        "/usr/local/cuda*"
    )
    
    for path in "${cleanup_paths[@]}"; do
        if ls $path 2>/dev/null; then
            log_info "清理: $path"
            rm -rf $path
        fi
    done
    
    # 移除仓库配置
    case $DISTRO_ID in
        ubuntu|debian)
            if [[ -f /etc/apt/sources.list.d/cuda*.list ]]; then
                log_info "移除CUDA仓库配置"
                rm -f /etc/apt/sources.list.d/cuda*.list
                rm -f /usr/share/keyrings/*cuda*
                apt update || true
            fi
            ;;
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            if [[ -f /etc/yum.repos.d/cuda*.repo ]]; then
                log_info "移除CUDA仓库配置"
                rm -f /etc/yum.repos.d/cuda*.repo
            fi
            ;;
        opensuse*|sles)
            if zypper lr | grep -q cuda; then
                log_info "移除CUDA仓库"
                zypper removerepo cuda-* 2>/dev/null || true
            fi
            ;;
    esac
}

# 更新initramfs
update_initramfs() {
    log_step "更新initramfs..."
    
    case $DISTRO_ID in
        ubuntu|debian)
            update-initramfs -u || log_warning "更新initramfs失败"
            ;;
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            if command -v dracut &> /dev/null; then
                dracut -f || log_warning "更新initramfs失败"
            fi
            ;;
        opensuse*|sles)
            mkinitrd || log_warning "更新initramfs失败"
            ;;
        azurelinux|mariner)
            if command -v dracut &> /dev/null; then
                dracut -f || log_warning "更新initramfs失败"
            fi
            ;;
    esac
}

# 恢复显示管理器
restore_display_managers() {
    if [[ -f /tmp/stopped_display_managers ]]; then
        log_step "恢复显示管理器..."
        
        local stopped_dms
        read -r stopped_dms < /tmp/stopped_display_managers
        
        for dm in $stopped_dms; do
            log_info "启动显示管理器: $dm"
            systemctl start "$dm" || log_warning "无法启动 $dm"
        done
        
        rm -f /tmp/stopped_display_managers
    fi
}

# 验证卸载
verify_uninstall() {
    log_step "验证卸载结果..."
    
    local issues=()
    
    # 检查内核模块
    if lsmod | grep -q nvidia; then
        issues+=("NVIDIA内核模块仍在加载")
    fi
    
    # 检查nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        issues+=("nvidia-smi命令仍然存在")
    fi
    
    # 检查包
    case $DISTRO_ID in
        ubuntu|debian)
            if dpkg -l | grep -q nvidia; then
                issues+=("仍有NVIDIA包未卸载")
            fi
            ;;
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            if rpm -qa | grep -q nvidia; then
                issues+=("仍有NVIDIA包未卸载")
            fi
            ;;
    esac
    
    if [[ ${#issues[@]} -eq 0 ]]; then
        log_success "NVIDIA驱动已完全卸载"
        return 0
    else
        log_warning "发现以下问题:"
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
        log_info "这些问题可能在重启后解决"
        return 1
    fi
}

# 显示后续步骤
show_next_steps() {
    echo
    log_success "NVIDIA驱动卸载完成！"
    echo
    echo -e "${GREEN}卸载摘要:${NC}"
    echo "- 发行版: $DISTRO_ID $DISTRO_VERSION"
    echo "- 强制模式: $(if $FORCE_UNINSTALL; then echo "是"; else echo "否"; fi)"
    echo "- 保留配置: $(if $KEEP_CONFIGS; then echo "是"; else echo "否"; fi)"
    echo "- 深度清理: $(if $CLEAN_ALL; then echo "是"; else echo "否"; fi)"
    echo
    echo -e "${YELLOW}后续步骤:${NC}"
    echo "1. 重启系统以完全清理NVIDIA驱动"
    echo "2. 重启后系统将使用默认显卡驱动"
    echo "3. 如需重新安装NVIDIA驱动，请运行nvidia-install.sh"
    echo
    echo -e "${BLUE}注意事项:${NC}"
    echo "• nouveau开源驱动将在重启后自动启用"
    echo "• 所有CUDA应用程序将无法运行"
    echo "• 可能需要重新配置显示设置"
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "=============================================="
    echo "  NVIDIA驱动卸载脚本 v1.0"
    echo "=============================================="
    echo -e "${NC}"
    
    # 解析参数
    parse_arguments "$@"
    
    # 检查权限
    check_root
    
    # 检测系统
    detect_distro
    
    # 检测NVIDIA安装
    detect_nvidia_installation
    
    # 显示卸载计划
    show_uninstall_plan
    
    # 开始卸载
    echo
    log_info "开始NVIDIA驱动卸载过程..."
    
    # 停止服务
    stop_nvidia_services
    
    # 停止GPU进程
    stop_gpu_processes
    
    # 卸载内核模块
    local modules_unloaded=true
    if ! unload_nvidia_modules; then
        modules_unloaded=false
        log_warning "部分内核模块未能卸载，需要重启后完成"
    fi
    
    # 卸载runfile
    uninstall_runfile
    
    # 卸载包
    uninstall_packages
    
    # 清理配置
    cleanup_configs
    
    # 深度清理
    deep_cleanup
    
    # 更新initramfs
    update_initramfs
    
    # 验证卸载
    local verification_passed=true
    if ! verify_uninstall; then
        verification_passed=false
    fi
    
    # 恢复显示管理器
    restore_display_managers
    
    # 显示结果
    show_next_steps
    
    # 决定是否重启
    echo
    if [[ "$REBOOT_AFTER" == "true" ]] || [[ "$modules_unloaded" == "false" ]]; then
        if [[ "$modules_unloaded" == "false" ]]; then
            log_info "由于内核模块无法完全卸载，需要重启系统"
        else
            log_info "自动重启已启用"
        fi
        log_info "正在重启系统..."
        reboot
    elif [[ "$AUTO_YES" == "true" ]]; then
        if [[ "$verification_passed" == "true" ]]; then
            log_success "卸载完成，建议重启系统"
        else
            log_warning "卸载可能不完整，建议重启系统"
        fi
    else
        if confirm "是否现在重启系统？" "N"; then
            log_info "正在重启系统..."
            reboot
        else
            log_info "请稍后手动重启系统以完成卸载"
        fi
    fi
}

# 运行主函数
main "$@"