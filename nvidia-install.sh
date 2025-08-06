#!/bin/bash

# NVIDIA 驱动一键安装脚本
# NVIDIA Driver One-Click Installer

# Author: PEScn @ EM-GeekLab
# Modified: 2025-07-09
# License: MIT
# GitHub: https://github.com/EM-GeekLab/nvidia-driver-installer
# Website: https://nvidia-install.online
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

set -e

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

# ================ 语言包定义 ===================
declare -A LANG_PACK_ZH_CN

# 中文语言包
LANG_PACK_ZH_CN=(
    ["exit.handler.receive_signal"]="收到信号:"
    ["exit.handler.exit_code"]="退出码:"
    ["exit.handler.script_interrupted"]="脚本被下列信号中断:"
    ["exit.handler.state_saved_for_resume"]="保存中断状态，可使用相同命令继续安装"
    ["exit.handler.temp_files_starting"]="开始清理临时文件..."
    ["clean.release_lock_file"]="释放锁文件"
    ["state.lock.error.another_install_running"]="另一个安装进程正在运行, PID: "
    ["state.lock.cleaning_orphaned_file"]="发现孤立的锁文件，将清理"
    ["state.lock.created"]="创建安装锁:"
    ["exit.code.prompt"]="错误码:"
    ["exit_code.success"]="成功完成"
    ["exit_code.permission"]="权限和环境错误 (1-9):"
    ["exit_code.permission.no_root"]="非root权限运行"
    ["exit_code.permission.fs_denied"]="文件系统权限不足"
    ["exit_code.permission.state_dir_failed"]="状态目录创建失败"
    ["exit_code.hardware"]="硬件检测错误 (10-19):"
    ["exit_code.hardware.no_gpu_detected"]="未检测到NVIDIA GPU"
    ["exit_code.hardware.lspci_unavailable"]="lspci命令不可用"
    ["exit_code.hardware.gpu_arch_incompatible"]="GPU架构不兼容"
    ["exit_code.compatibility"]="系统兼容性错误 (20-29):"
    ["exit_code.compatibility.unsupported_os"]="不支持的操作系统"
    ["exit_code.compatibility.unsupported_version"]="不支持的发行版版本"
    ["exit_code.compatibility.unsupported_arch"]="不支持的系统架构"
    ["exit_code.config"]="参数和配置错误 (30-39):"
    ["exit_code.config.invalid_args"]="无效的命令行参数"
    ["exit_code.config.invalid_install_type"]="无效的安装类型"
    ["exit_code.config.module_arch_mismatch"]="模块类型与GPU架构不匹配"
    ["exit_code.secure_boot"]="Secure Boot相关错误 (40-49):"
    ["exit_code.secure_boot.user_exit"]="Secure Boot启用，用户选择退出"
    ["exit_code.secure_boot.auto_failed"]="Secure Boot启用，自动化模式无法处理"
    ["exit_code.secure_boot.mok_operation_failed"]="MOK密钥操作失败"
    ["exit_code.secure_boot.mok_tools_missing"]="缺少MOK管理工具"
    ["exit_code.conflict"]="现有驱动冲突 (50-59):"
    ["exit_code.conflict.existing_driver_user_exit"]="现有驱动冲突，用户选择退出"
    ["exit_code.conflict.driver_uninstall_failed"]="现有驱动卸载失败"
    ["exit_code.conflict.nouveau_disable_failed"]="nouveau驱动禁用失败"
    ["exit_code.network"]="网络和下载错误 (60-69):"
    ["exit_code.network.connection_failed"]="网络连接失败"
    ["exit_code.network.repo_download_failed"]="仓库下载失败"
    ["exit_code.network.keyring_download_failed"]="CUDA keyring下载失败"
    ["exit_code.pkg_manager"]="包管理器错误 (70-79):"
    ["exit_code.pkg_manager.unavailable"]="包管理器不可用"
    ["exit_code.pkg_manager.repo_add_failed"]="仓库添加失败"
    ["exit_code.pkg_manager.dependency_install_failed"]="依赖包安装失败"
    ["exit_code.pkg_manager.kernel_headers_failed"]="内核头文件安装失败"
    ["exit_code.pkg_manager.nvidia_install_failed"]="NVIDIA驱动安装失败"
    ["exit_code.system_state"]="系统状态错误 (80-89):"
    ["exit_code.system_state.kernel_version_issue"]="内核版本问题"
    ["exit_code.system_state.dkms_build_failed"]="DKMS构建失败"
    ["exit_code.system_state.module_signing_failed"]="模块签名失败"
    ["exit_code.system_state.driver_verification_failed"]="驱动验证失败"
    ["exit_code.state_management"]="状态管理错误 (90-99):"
    ["exit_code.state_management.rollback_file_missing"]="回滚文件缺失"
    ["exit_code.state_management.rollback_failed"]="回滚操作失败"
    ["exit_code.state_management.state_file_corrupted"]="状态文件损坏"
    ["exit_code.user_cancelled"]="用户取消安装"
    ["exit_code.unknown_code"]="未知错误码:"
    ["auto_yes.prompt"]="自动确认命令:"
    ["select_option.prompt.range"]="请选择，可选范围:"
    ["select_option.prompt.default"]="默认:"
    ["select_option.prompt.invalid_choice"]="无效选择，可选范围:"
    ["args.info.auto_mode_enabled"]="自动化模式已启用"
    ["args.info.quiet_mode_enabled"]="静默模式已启用"
    ["args.error.invalid_module_type"]="无效的模块类型:"
    ["args.info.valid_types"]="(应为 open 或 proprietary)"
    ["args.error.unknown_arg"]="未知选项:"
    ["args.error.invalid_install_type"]="无效的安装类型:"
    ["state.dir.error.create_state_dir"]="无法创建状态目录"
    ["cleanup.success.state_file_deleted"]="状态文件已删除"
    ["cleanup.success.rollback_file_deleted"]="回滚文件已删除"
    ["cleanup.failed.starting"]="清理失败的安装状态..."
    ["cleanup.failed.previous_state_found"]="发现之前的安装状态："
    ["cleanup.failed.confirm_cleanup"]="是否清理这些状态文件？"
    ["cleanup.failed.state_cleaned"]="安装状态已清理"
    ["cleanup.failed.no_state_found"]="未发现失败的安装状态"
    ["cleanup.success.starting"]="清理安装状态..."
    ["cleanup.success.all_states_cleaned"]="安装完成，所有状态已清理"
    ["rollback.starting"]="开始回滚安装..."
    ["rollback.warning.changes_will_be_undone"]="这将撤销所有通过此脚本进行的更改"
    ["rollback.confirm.proceed"]="是否继续回滚？"
    ["rollback.info.executing"]="执行回滚"
    ["rollback.warning.partial_failure"]="回滚操作失败"
    ["rollback.error.rollback_file_missing"]="未找到回滚信息文件"
    ["rollback.error.partial_failure"]="部分回滚操作失败，系统可能处于不一致状态"
    ["rollback.success"]="回滚完成"
    ["rollback.error.user_cancelled"]="用户取消回滚操作"
    ["detect.os.starting"]="检测操作系统发行版..."
    ["detect.os.error.unsupported_arch"]="仅支持 x86_64 和 aarch64，您当前架构为:"
    ["detect.os.error.cannot_detect"]="无法检测操作系统发行版"
    ["detect.os.success"]="检测到发行版:"
    ["detect.gpu.starting"]="检查NVIDIA GPU并确定架构兼容性..."
    ["detect.gpu.error.lspci_missing"]="lspci命令未找到，请安装pciutils包"
    ["detect.gpu.error.no_gpu_found"]="未检测到NVIDIA GPU"
    ["detect.gpu.success.detected"]="检测到NVIDIA GPU"
    ["detect.gpu.success.support_open"]="支持开源内核模块"
    ["detect.gpu.error.not_support_open"]="不支持开源内核模块"
    ["detect.gpu.info.use_proprietary"]="将使用专有内核模块"
    ["detect.gpu.warning.unknown_device_id"]="无法确定设备ID"
    ["detect.gpu.old_gpu_found_warning"]="检测到不兼容开源驱动的GPU！"
    ["detect.gpu.open_support_prompt"]="开源驱动支持情况："
    ["detect.gpu.info.open_support_list"]="✅ 支持: Turing, Ampere, Ada Lovelace, Blackwell (RTX 16xx/20xx/30xx/40xx/50xx系列)"
    ["detect.gpu.info.open_unsupport_list"]="❌ 不支持: Maxwell, Pascal, Volta (GTX 9xx/10xx系列, Tesla V100等)"
    ["detect.gpu.incompatible.solution_prompt"]="解决方案："
    ["detect.gpu.incompatible.solution_option1"]="1. 使用专有模块 (推荐)"
    ["detect.gpu.incompatible.solution_option2"]="2. 仅针对兼容的GPU使用开源模块 (高级用户)"
    ["detect.gpu.incompatible.confirm"]="是否切换到专有模块？"
    ["detect.gpu.incompatible.switch"]="切换到专有内核模块"
    ["detect.gpu.incompatible.continue_warning"]="继续使用开源模块，但可能导致部分GPU无法正常工作"
    ["detect.gpu.incompatible.auto_mode_switch"]="自动化模式：切换到专有内核模块以确保兼容性"
    ["detect.gpu.summary.header"]="GPU配置摘要:"
    ["detect.gpu.summary.header.gpu_number"]="GPU编号"
    ["detect.gpu.summary.header.architecture"]="架构"
    ["detect.gpu.summary.header.module_type"]="模块类型"
    ["detect.gpu.summary.value.open_module"]="开源模块"
    ["detect.gpu.summary.value.proprietary_module_fallback"]="专有模块*"
    ["detect.gpu.summary.value.proprietary_module"]="专有模块"
    ["detect.gpu.summary.note.fallback"]="* 标记的GPU将回退到专有模块"
    ["detect.distro_support.starting"]="检查发行版支持情况..."
    ["detect.distro_support.warning.rhel7_eol"]="RHEL 7 已EOL，建议升级"
    ["detect.distro_support.error.unsupported_rhel_version"]="不支持的RHEL版本:"
    ["detect.distro_support.warning.fedora_unofficial"]="可能不是官方支持版本"
    ["detect.distro_support.error.fedora_incompatible"]="可能不兼容"
    ["detect.distro_support.warning.ubuntu1804_eol"]="Ubuntu 18.04 已EOL"
    ["detect.distro_support.warning.ubuntu_maybe_supported"]="可能支持的Ubuntu版本:"
    ["detect.distro_support.warning.ubuntu_unspecified"]="未明确支持的Ubuntu版本:"
    ["detect.distro_support.warning.debian11_needs_tuning"]="Debian 11可能需要手动调整"
    ["detect.distro_support.warning.debian_unspecified"]="未明确支持的Debian版本:"
    ["detect.distro_support.warning.suse_maybe_supported"]="可能支持的SUSE版本:"
    ["detect.distro_support.warning.amzn2_needs_tuning"]="Amazon Linux 2可能需要调整"
    ["detect.distro_support.error.unsupported_amzn_version"]="不支持的Amazon Linux版本:"
    ["detect.distro_support.warning.azure_maybe_supported"]="可能支持的Azure Linux版本:"
    ["detect.distro_support.error.unsupported_kylin_version"]="未明确支持的麒麟操作系统版本"
    ["detect.distro_support.error.unknown_distro"]="未知或不支持的发行版:"
    ["detect.distro_support.success.fully_supported"]="发行版完全支持:"
    ["detect.distro_support.warning.partially_supported"]="发行版部分支持:"
    ["detect.distro_support.prompt.confirm.continue_install"]="是否继续安装？"
    ["detect.distro_support.user_cancelled"]="用户取消安装"
    ["detect.distro_support.error.unsupported"]="发行版不支持:"
    ["detect.distro_support.info.supported_list_header"]="支持的发行版:"
    ["detect.distro_support.prompt.confirm.force_install"]="是否强制继续安装？"
    ["detect.distro_support.warning.force_mode_issues"]="强制安装模式，可能遇到兼容性问题"
    ["detect.existing_driver.skipping_check"]="跳过现有驱动检查"
    ["detect.existing_driver.starting"]="检查现有NVIDIA驱动安装..."
    ["detect.existing_driver.warning.kernel_module_loaded"]="检测到已加载的NVIDIA内核模块："
    ["detect.existing_driver.warning.pkg_manager_install"]="检测到通过包管理器安装的NVIDIA驱动："
    ["detect.existing_driver.warning.runfile_install"]="检测到通过runfile安装的NVIDIA驱动"
    ["detect.existing_driver.warning.ppa_found"]="检测到graphics-drivers PPA"
    ["detect.existing_driver.warning.rpm_fusion_found"]="检测到RPM Fusion仓库"
    ["detect.existing_driver.error.driver_found"]="检测到现有NVIDIA驱动安装！"
    ["detect.existing_driver.info.install_method"]="安装方法:"
    ["detect.existing_driver.prompt.user_choice"]="建议操作：\n1. 卸载现有驱动后重新安装 (推荐)\n2. 强制重新安装 (可能导致冲突)\n3. 跳过检查继续安装 (高级用户)\n4. 退出安装"
    ["prompt.select_option.please_select"]="请选择操作"
    ["prompt.select_option.existing_driver.choice_uninstall"]="卸载现有驱动后重新安装"
    ["prompt.select_option.existing_driver.choice_force"]="强制重新安装"
    ["prompt.select_option.existing_driver.choice_skip"]="跳过检查继续安装"
    ["prompt.select_option.existing_driver.choice_exit"]="退出安装"
    ["detect.existing_driver.warning.force_reinstall_mode"]="强制重新安装模式"
    ["detect.existing_driver.warning.skip_mode"]="跳过现有驱动检查"
    ["detect.existing_driver.exit.user_choice"]="用户选择退出以处理现有驱动"
    ["detect.existing_driver.warning.auto_mode_uninstall"]="自动化模式：卸载现有驱动后重新安装"
    ["detect.existing_driver.warning.force_mode_skip_uninstall"]="强制重新安装模式，跳过现有驱动处理"
    ["detect.existing_driver.success.no_driver_found"]="未检测到现有NVIDIA驱动"
    ["uninstall.existing_driver.starting"]="卸载现有NVIDIA驱动..."
    ["uninstall.existing_driver.info.using_runfile_uninstaller"]="使用nvidia-uninstall卸载runfile安装的驱动"
    ["uninstall.existing_driver.warning.runfile_uninstall_incomplete"]="runfile卸载可能不完整"
    ["uninstall.existing_driver.info.removing_kernel_modules"]="卸载NVIDIA内核模块"
    ["uninstall.existing_driver.warning.module_removal_failed"]="部分模块卸载失败，需要重启"
    ["uninstall.existing_driver.success"]="现有驱动卸载完成"
    ["secure_boot.check.starting"]="检测UEFI Secure Boot状态..."
    ["secure_boot.check.method"]="检测方法"
    ["secure_boot.check.disabled_or_unsupported"]="Secure Boot未启用或系统不支持UEFI"
    ["secure_boot.check.warning"]="重要警告"
    ["secure_boot.enabled.error_detected"]="检测到UEFI Secure Boot已启用！"
    ["secure_boot.enabled.why_is_problem"]="为什么这是个问题？"
    ["secure_boot.enabled.why_is_problem_detail"]="1. Secure Boot阻止加载未签名的内核模块\n2. NVIDIA驱动包含内核模块，必须正确签名才能加载\n3. 即使安装成功，驱动也无法工作，导致：\n   • 黑屏或图形显示异常\n   • CUDA/OpenCL不可用\n   • 多显示器不工作\n   • 系统可能无法启动"
    ["secure_boot.enabled.solutions"]="推荐解决方案（选择其一）："
    ["secure_boot.enabled.solution.disable"]="方案1: 禁用Secure Boot (最简单)"
    ["secure_boot.enabled.solution.disable_steps"]="1. 重启进入BIOS/UEFI设置\n2. 找到Security或Boot选项\n3. 禁用Secure Boot\n4. 保存并重启\n5. 重新运行此脚本"
    ["secure_boot.enabled.solution.sign"]="方案2: 使用MOK密钥签名 (保持Secure Boot)"
    ["secure_boot.enabled.solution.sign_steps"]="1. 安装必要工具: mokutil, openssl, dkms\n2. 生成Machine Owner Key (MOK)\n3. 将MOK注册到UEFI固件\n4. 配置DKMS自动签名NVIDIA模块\n5. 重新运行此脚本"
    ["secure_boot.enabled.solution.prebuilt"]="方案3: 使用预签名驱动 (如果可用)"
    ["secure_boot.enabled.solution.prebuilt_steps"]="某些发行版提供预签名的NVIDIA驱动：\n• Ubuntu: 可能通过ubuntu-drivers获得签名驱动\n• RHEL: 可能有预编译的签名模块\n• SUSE: 可能通过官方仓库获得"
    ["secure_boot.enabled.solution.mok_setup"]="🔧 自动配置MOK密钥 (高级选项)"
    ["secure_boot.enabled.solution.mok_setup_notice"]="此脚本可以帮助配置MOK密钥，但需要：\n• 在重启时手动确认MOK密钥\n• 记住设置的密码\n• 理解Secure Boot的安全影响"
    ["secure_boot.enabled.sign.detected"]="✓ 检测到现有MOK密钥文件"
    ["secure_boot.enabled.advice_footer"]="强烈建议: 在解决Secure Boot问题之前，不要继续安装NVIDIA驱动！"
    ["secure_boot.enabled.choose_action.prompt"]="请选择操作：\n1. 退出安装，我将手动解决Secure Boot问题\n2. 帮助配置MOK密钥 (高级用户)\n3. 强制继续安装 (不推荐，可能导致系统问题)"
    ["secure_boot.enabled.choice.exit"]="退出安装"
    ["secure_boot.enabled.choice.sign"]="配置MOK密钥"
    ["secure_boot.enabled.choice.force"]="强制继续安装"
    ["secure_boot.enabled.exit.cancelled_user_fix"]="安装已取消，请解决Secure Boot问题后重新运行"
    ["secure_boot.enabled.exit.useful_commands"]="有用的命令：\n• 检查Secure Boot状态: mokutil --sb-state\n• 检查现有MOK: mokutil --list-enrolled\n• 检查NVIDIA模块: lsmod | grep nvidia"
    ["secure_boot.enabled.exit.user_choice"]="用户选择退出以处理Secure Boot问题"
    ["secure_boot.enabled.warning.user_forced_install"]="用户选择强制继续安装，可能导致驱动无法工作"
    ["secure_boot.enabled.warning.auto_mode_existing_mok"]="自动化模式：检测到现有MOK密钥，继续安装"
    ["secure_boot.enabled.error.auto_mode_failure"]="自动化模式下无法处理Secure Boot问题"
    ["mok.setup.starting"]="配置MOK密钥签名..."
    ["mok.setup.error.tools_missing"]="缺少必要工具:"
    ["mok.setup.error.please_install_tools"]="请先安装这些工具："
    ["mok.setup.info.using_ubuntu_key"]="使用现有Ubuntu/Debian MOK密钥"
    ["mok.setup.info.using_dkms_key"]="使用现有DKMS MOK密钥"
    ["mok.setup.info.generating_new_key"]="生成新的MOK密钥..."
    ["mok.setup.error.generation_failed"]="MOK密钥生成失败"
    ["mok.setup.success.generation_complete"]="MOK密钥生成完成"
    ["mok.setup.info.enrolling_key"]="注册MOK密钥到UEFI固件..."
    ["mok.setup.enroll.important_note_header"]="重要说明："
    ["mok.setup.enroll.note"]="1. 系统将提示您输入一个一次性密码\n2. 请记住这个密码，重启时需要使用\n3. 建议使用简单的数字密码（考虑键盘布局）"
    ["mok.setup.error.enroll_failed"]="MOK密钥注册失败"
    ["mok.setup.success.enroll_queued"]="MOK密钥已排队等待注册"
    ["mok.setup.next_steps.header"]="下一步操作："
    ["mok.setup.enroll.next_steps"]="1. 脚本安装完成后，系统将重启\n2. 重启时会出现MOK Manager界面\n3. 选择 'Enroll MOK'\n4. 选择 'Continue'\n5. 选择 'Yes'\n6. 输入刚才设置的密码\n7. 系统将再次重启"
    ["mok.setup.next_steps.warning_english_interface"]="注意：MOK Manager界面可能使用英文，请仔细操作"
    ["dkms.signing.configuring"]="配置DKMS自动签名..."
    ["dkms.signing.success"]="DKMS自动签名配置完成"
    ["pre_check.starting"]="执行预安装检查..."
    ["root.partition.space.insufficient"]="根分区可用空间不足1GB，可能影响安装"
    ["pre_check.warning.vm_detected"]="检测到虚拟机环境:"
    ["pre_check.vm.note"]="注意事项：\n• 确保虚拟机已启用3D加速\n• 某些虚拟机可能不支持NVIDIA GPU直通\n• 容器环境可能需要特殊配置"
    ["pre_check.warning.custom_kernel_detected"]="检测到自定义内核:"
    ["pre_check.custom_kernel.note"]="自定义内核可能需要额外的DKMS配置"
    ["pre_check.success"]="预安装检查完成"
    ["repo.add.exists"]="仓库已存在，跳过添加"
    ["repo.add.adding"]="添加仓库:"
    ["pkg_install.info.installing_missing"]="安装缺失的包:"
    ["pkg_install.info.all_packages_exist"]="所有包已安装，跳过安装步骤"
    ["repo.enable.already_done"]="第三方仓库已启用，跳过此步骤"
    ["repo.enable.starting"]="启用必要的仓库和依赖..."
    ["repo.enable.error.rhel_appstream"]="无法启用appstream仓库"
    ["repo.enable.error.rhel_baseos"]="无法启用baseos仓库"
    ["repo.enable.error.rhel_crb"]="无法启用codeready-builder仓库"
    ["repo.enable.error.suse_packagehub"]="无法启用PackageHub"
    ["kernel_headers.install.already_done"]="内核头文件已安装，跳过此步骤"
    ["kernel_headers.install.starting"]="安装内核头文件和开发包..."
    ["repo.local.setup.starting"]="设置本地仓库安装..."
    ["repo.local.setup.downloading"]="下载本地仓库包:"
    ["repo.network.setup.starting"]="设置网络仓库..."
    ["repo.network.setup.installing_keyring"]="下载并安装cuda-keyring"
    ["repo.network.setup.keyring_exists"]="cuda-keyring已安装，跳过"
    ["repo.nvidia.add.already_done"]="NVIDIA仓库已添加，跳过此步骤"
    ["repo.nvidia.add.starting"]="添加NVIDIA官方仓库..."
    ["dnf_module.enable.starting"]="启用DNF模块..."
    ["nvidia_driver.install.starting"]="安装NVIDIA驱动"
    ["nvidia_driver.type.open"]="开源模块"
    ["nvidia_driver.type.proprietary"]="专有模块"
    ["nouveau.disable.starting"]="禁用nouveau开源驱动..."
    ["nouveau.disable.warning.detected_running"]="检测到nouveau驱动正在运行"
    ["nouveau.disable.warning.processes_using_drm"]="个进程正在使用图形设备"
    ["nouveau.disable.info.stopping_display_manager"]="尝试停止图形服务以释放nouveau驱动..."
    ["nouveau.disable.info.stop_display_manager"]="停止显示管理器:"
    ["nouveau.disable.warning.failed_stopping_display_manager"]="无法停止"
    ["nouveau.disable.info.switching_to_text_mode"]="切换到文本模式..."
    ["nouveau.disable.info.unloading_module"]="尝试卸载nouveau驱动模块..."
    ["nouveau.disable.info.unload_module"]="尝试卸载模块:"
    ["nouveau.disable.success.module_unloaded"]="成功卸载模块:"
    ["nouveau.disable.warning.module_unload_failed"]="无法卸载模块:"
    ["nouveau.disable.error.still_running_reboot_needed"]="nouveau模块仍在运行，需要重启系统才能完全禁用"
    ["nouveau.disable.success.module_unloaded_all"]="nouveau模块已成功卸载"
    ["nouveau.disable.info.not_running"]="nouveau驱动未运行"
    ["nouveau.disable.info.creating_blacklist"]="创建nouveau黑名单配置..."
    ["nouveau.disable.info.updating_initramfs"]="更新initramfs以确保nouveau在启动时被禁用..."
    ["nouveau.disable.warning.initramfs_update_failed"]="更新initramfs失败，可能影响下次启动"
    ["nouveau.disable.warning.dracut_missing"]="dracut命令未找到，无法更新initramfs"
    ["nouveau.disable.info.restarting_display_manager"]="nouveau已禁用，重启显示服务..."
    ["nouveau.disable.info.restart_display_manager"]="重启显示管理器"
    ["nouveau.disable.warning.restart_failed"]="无法重启"
    ["nouveau.disable.warning.reboot_required_final"]="nouveau驱动需要重启系统才能完全禁用"
    ["nouveau.disable.error.reboot_needed_header"]="⚠️  重要提醒：需要重启系统"
    ["nouveau.disable.error.reboot_needed_note"]="nouveau驱动仍在运行中，必须重启系统后才能继续安装NVIDIA驱动\n这通常发生在以下情况：\n• 有图形程序正在使用nouveau驱动\n• nouveau模块被其他模块依赖\n• 系统正在图形模式下运行"
    ["nouveau.disable.info.auto_mode_reboot"]="自动化模式：保存当前状态，重启后将自动继续安装"
    ["nouveau.disable.confirm.reboot_now"]="是否现在重启系统？重启后请重新运行安装脚本"
    ["nouveau.disable.info.rebooting_now"]="正在重启系统，重启后请重新运行安装脚本..."
    ["nouveau.disable.exit.user_refused_reboot"]="用户选择不重启，无法继续安装"
    ["nouveau.disable.success.continue_install"]="nouveau驱动已成功禁用，继续安装NVIDIA驱动"
    ["persistence_daemon.enable.starting"]="启用NVIDIA persistence daemon..."
    ["persistence_daemon.enable.success"]="NVIDIA persistence daemon已启用"
    ["persistence_daemon.enable.warning.service_not_found"]="nvidia-persistenced服务未找到"
    ["verify.starting"]="验证NVIDIA驱动安装..."
    ["verify.success.driver_loaded"]="NVIDIA驱动已加载:"
    ["verify.warning.module_not_loaded"]="NVIDIA驱动模块未加载"
    ["verify.success.smi_available"]="nvidia-smi工具可用"
    ["verify.info.testing_driver"]="测试NVIDIA驱动功能..."
    ["verify.success.driver_working"]="NVIDIA驱动工作正常！"
    ["verify.error.smi_failed"]="nvidia-smi执行失败，驱动未正常工作"
    ["verify.warning.smi_unavailable"]="nvidia-smi命令不可用"
    ["verify.info.loaded_modules"]="已加载的NVIDIA模块:"
    ["common.unknown"]="未知"
    ["verify.info.module_version"]="模块版本:"
    ["cleanup.install_files.starting"]="清理安装文件..."
    ["final.success.header"]="NVIDIA驱动安装完成！"
    ["final.summary.header"]="安装摘要:"
    ["final.summary.distro"]="发行版"
    ["final.summary.arch"]="架构"
    ["final.summary.module_type"]="模块类型"
    ["module.type.open_kernel"]="开源内核模块"
    ["module.type.proprietary_kernel"]="专有内核模块"
    ["repo.type.local"]="本地仓库"
    ["repo.type.network"]="网络仓库"
    ["final.next_steps.header"]="后续步骤:"
    ["final.next_steps.working.note"]="1. ✅ 驱动已正常工作，可立即使用NVIDIA GPU\n2. 如需安装CUDA Toolkit，请访问: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/\n3. 技术支持论坛: https://forums.developer.nvidia.com/c/gpu-graphics/linux/148\n4. 如遇问题，可回滚安装，请运行"
    ["final.next_steps.not_working.note"]="1. 重启系统以确保驱动完全生效\n2. 重启后运行 'nvidia-smi' 验证安装\n3. 如需安装CUDA Toolkit，请访问: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/\n4. 技术支持论坛: https://forums.developer.nvidia.com/c/gpu-graphics/linux/148\n5. 如遇问题，可回滚安装，请运行"
    ["final.next_steps.secure_boot.header"]="🔐 Secure Boot提醒："
    ["final.next_steps.secure_boot.working"]="6. ✅ MOK密钥已正确配置，驱动正常工作"
    ["final.next_steps.secure_boot.error"]="6. 重启时如果出现MOK Manager界面，请选择 'Enroll MOK' 并输入密码\n7. 如果驱动无法加载，检查: sudo dmesg | grep nvidia\n8. 验证模块签名: modinfo nvidia | grep sig"
    ["final.notes.compute.header"]="计算专用安装说明:"
    ["final.notes.compute.notes"]="- 此安装不包含桌面显卡组件 (OpenGL, Vulkan, X驱动等)\n- 适用于计算集群或无显示器的工作站\n- 如需添加桌面组件，可稍后安装相应包"
    ["final.notes.desktop.header"]="桌面专用安装说明:"
    ["final.notes.desktop.notes"]="- 此安装不包含CUDA计算组件\n- 适用于纯桌面/游戏用途\n- 如需CUDA支持，可稍后安装nvidia-driver-cuda包"
    ["permission.error.root_required"]="此脚本需要root权限运行，请使用:"
    ["main.info.non_interactive_quiet_mode"]="检测到非交互环境，启用静默模式"
    ["main.header.title"]="NVIDIA驱动一键安装脚本"
    ["main.header.auto_mode_subtitle"]="无交互自动化模式"
    ["main.resume.warning_incomplete_state_found"]="检测到未完成的安装状态:"
    ["main.resume.confirm_resume_install"]="是否从上次中断处继续安装？"
    ["main.resume.info_resuming"]="从断点继续安装"
    ["main.resume.info_restarting"]="清理状态文件并重新开始"
    ["main.config_summary.header"]="安装配置:"
    ["main.config_summary.distro"]="发行版:"
    ["main.config_summary.module_type"]="模块类型:"
    ["main.config_summary.install_type"]="安装类型:"
    ["main.config_summary.repo_type"]="仓库类型:"
    ["main.config_summary.auto_mode"]="自动化模式:"
    ["main.config_summary.force_reinstall"]="强制重装:"
    ["main.config_summary.auto_reboot"]="自动重启:"
    ["common.yes"]="是"
    ["common.no"]="否"
    ["main.config_summary.confirm"]="是否继续安装？"
    ["main.config_summary.user_cancel"]="用户取消安装"
    ["main.install.starting"]="开始NVIDIA驱动安装过程..."
    ["main.reboot_logic.success_no_reboot_needed"]="🎉 NVIDIA驱动安装成功并正常工作！"
    ["main.reboot_logic.success_smi_passed"]="nvidia-smi测试通过，驱动已可正常使用，无需重启系统。"
    ["main.reboot_logic.info_rebooting_on_user_request"]="尽管驱动已正常工作，但用户启用了自动重启选项"
    ["main.reboot_logic.info_rebooting_now"]="正在重启系统..."
    ["main.reboot_logic.success_auto_mode_no_reboot"]="自动化模式：驱动安装完成，无需重启"
    ["main.reboot_logic.confirm_optional_reboot"]="驱动已正常工作，是否仍要重启系统？"
    ["main.reboot_logic.info_reboot_skipped"]="已跳过重启，可立即使用NVIDIA驱动"
    ["main.reboot_logic.warning_reboot_required"]="⚠️  NVIDIA驱动需要重启系统才能正常工作"
    ["main.reboot_logic.warning_smi_failed_reboot_required"]="nvidia-smi测试失败，必须重启系统以完成驱动安装。"
    ["main.reboot_logic.reason_nouveau"]="原因：nouveau驱动无法完全卸载"
    ["main.reboot_logic.reason_module_load"]="原因：NVIDIA驱动模块需要重启后才能正常加载"
    ["main.reboot_logic.info_auto_mode_rebooting"]="自动重启模式：正在重启系统..."
    ["main.reboot_logic.confirm_reboot_now"]="是否现在重启系统？"
    ["main.reboot_logic.warning_manual_reboot_needed"]="请手动重启系统以完成驱动安装"
    ["main.reboot_logic.info_verify_after_reboot"]="重启后可运行 'nvidia-smi' 验证驱动是否正常工作"
)

declare -A LANG_PACK_EN_US

# 英文语言包
LANG_PACK_EN_US=(
    ["exit.handler.receive_signal"]="Received signal:"
    ["exit.handler.exit_code"]="Exit code:"
    ["exit.handler.script_interrupted"]="Script interrupted by signal:"
    ["exit.handler.state_saved_for_resume"]="Installation state saved. You can try to resume on the next run."
    ["exit.handler.temp_files_starting"]="Cleaning up temporary files..."
    ["clean.release_lock_file"]="Releasing lock file:"
    ["state.lock.error.another_install_running"]="Another installation process is running (PID:"
    ["state.lock.cleaning_orphaned_file"]="Cleaning up orphaned lock file..."
    ["state.lock.created"]="Install lock created:"
    ["exit.code.prompt"]="Exit code:"
    ["exit_code.success"]="Operation successful"
    ["exit_code.permission"]="Permission and environment errors (1-9):"
    ["exit_code.permission.no_root"]="Root privileges are required"
    ["exit_code.permission.fs_denied"]="Insufficient file system permissions"
    ["exit_code.permission.state_dir_failed"]="Failed to create state directory"
    ["exit_code.hardware"]="Hardware Detection Error (10-19):"
    ["exit_code.hardware.no_gpu_detected"]="No NVIDIA GPU detected"
    ["exit_code.hardware.lspci_unavailable"]="lspci command unavailable"
    ["exit_code.hardware.gpu_arch_incompatible"]="GPU architecture incompatible with selected modules"
    ["exit_code.compatibility"]="System Compatibility Errors (20-29):"
    ["exit_code.compatibility.unsupported_os"]="Unsupported operating system"
    ["exit_code.compatibility.unsupported_version"]="Unsupported operating system version"
    ["exit_code.compatibility.unsupported_arch"]="Unsupported system architecture"
    ["exit_code.config"]="Parameter and Configuration Errors (30-39):"
    ["exit_code.config.invalid_args"]="Invalid command-line arguments"
    ["exit_code.config.invalid_install_type"]="Invalid installation type"
    ["exit_code.config.module_arch_mismatch"]="Module and architecture mismatch"
    ["exit_code.secure_boot"]="Secure Boot Errors (40-49):"
    ["exit_code.secure_boot.user_exit"]="User chose to exit to handle Secure Boot"
    ["exit_code.secure_boot.auto_failed"]="Secure Boot is enabled and cannot be handled automatically"
    ["exit_code.secure_boot.mok_operation_failed"]="MOK key operation failed"
    ["exit_code.secure_boot.mok_tools_missing"]="MOK tools are missing"
    ["exit_code.conflict"]="Existing Driver Conflicts (50-59):"
    ["exit_code.conflict.existing_driver_user_exit"]="User chose to exit due to existing driver"
    ["exit_code.conflict.driver_uninstall_failed"]="Failed to uninstall existing driver"
    ["exit_code.conflict.nouveau_disable_failed"]="Failed to disable nouveau driver"
    ["exit_code.network"]="Network and Download Errors (60-69):"
    ["exit_code.network.connection_failed"]="Network connection failed"
    ["exit_code.network.repo_download_failed"]="Repository file download failed"
    ["exit_code.network.keyring_download_failed"]="Keyring download failed"
    ["exit_code.pkg_manager"]="Package Manager Errors (70-79):"
    ["exit_code.pkg_manager.unavailable"]="Package manager unavailable"
    ["exit_code.pkg_manager.repo_add_failed"]="Failed to add repository"
    ["exit_code.pkg_manager.dependency_install_failed"]="Dependency installation failed"
    ["exit_code.pkg_manager.kernel_headers_failed"]="Failed to install kernel headers"
    ["exit_code.pkg_manager.nvidia_install_failed"]="Failed to install NVIDIA driver packages"
    ["exit_code.system_state"]="System status error (80-89):"
    ["exit_code.system_state.kernel_version_issue"]="Kernel version mismatch issue"
    ["exit_code.system_state.dkms_build_failed"]="DKMS module build failed"
    ["exit_code.system_state.module_signing_failed"]="Module signing failed"
    ["exit_code.system_state.driver_verification_failed"]="Driver validation failed (nvidia-smi)"
    ["exit_code.state_management"]="State management error (90-99):"
    ["exit_code.state_management.rollback_file_missing"]="Rollback file is missing"
    ["exit_code.state_management.rollback_failed"]="Rollback operation failed"
    ["exit_code.state_management.state_file_corrupted"]="State file is corrupt or another instance is running"
    ["exit_code.user_cancelled"]="Operation cancelled by user"
    ["exit_code.unknown_code"]="Unknown error, exit code:"
    ["auto_yes.prompt"]="Auto-yes mode, automatically confirming:"
    ["select_option.prompt.range"]="Please enter your choice"
    ["select_option.prompt.default"]="default"
    ["select_option.prompt.invalid_choice"]="Invalid choice, please enter a number between"
    ["args.error.invalid_module_type"]="Invalid module type:"
    ["args.info.valid_types"]="Valid types are 'open' or 'proprietary'"
    ["args.error.unknown_arg"]="Unknown argument:"
    ["args.error.invalid_install_type"]="Invalid installation type."
    ["args.info.auto_mode_enabled"]="Automation mode enabled."
    ["args.info.quiet_mode_enabled"]="Quiet mode enabled."
    ["state.dir.error.create_state_dir"]="Failed to create state directory:"
    ["cleanup.failed.starting"]="Starting cleanup of previous failed installation state..."
    ["cleanup.failed.previous_state_found"]="Found previous installation state file:"
    ["cleanup.failed.confirm_cleanup"]="Do you want to delete these state files and start over?"
    ["cleanup.failed.state_cleaned"]="State files have been cleaned up."
    ["cleanup.failed.no_state_found"]="No failed installation state found, no cleanup needed."
    ["cleanup.success.starting"]="Starting cleanup of post-installation state files..."
    ["cleanup.success.state_file_deleted"]="Deleted state file:"
    ["cleanup.success.rollback_file_deleted"]="Deleted rollback file:"
    ["cleanup.success.all_states_cleaned"]="All state files have been cleaned up."
    ["rollback.starting"]="Starting installation rollback..."
    ["rollback.error.rollback_file_missing"]="Rollback file not found, cannot proceed:"
    ["rollback.warning.changes_will_be_undone"]="This operation will undo the changes made during installation."
    ["rollback.confirm.proceed"]="Are you sure you want to proceed with the rollback?"
    ["rollback.info.executing"]="Executing rollback action:"
    ["rollback.warning.partial_failure"]="Partial rollback failed, please check manually:"
    ["rollback.error.partial_failure"]="Rollback did not complete successfully."
    ["rollback.success"]="Rollback completed successfully."
    ["rollback.error.user_cancelled"]="Rollback cancelled by user."
    ["detect.os.starting"]="Detecting operating system..."
    ["detect.os.error.unsupported_arch"]="Unsupported system architecture:"
    ["detect.os.success"]="Detected operating system:"
    ["detect.os.error.cannot_detect"]="Cannot detect operating system because /etc/os-release is missing."
    ["detect.gpu.starting"]="Detecting NVIDIA GPU..."
    ["detect.gpu.error.lspci_missing"]="\"lspci\" command not found. Please install pciutils."
    ["detect.gpu.error.no_gpu_found"]="No NVIDIA GPU detected. Exiting script."
    ["detect.gpu.success.detected"]="Detected GPU"
    ["detect.gpu.success.support_open"]="supports open kernel modules."
    ["detect.gpu.error.not_support_open"]="does not support open kernel modules, proprietary modules are required."
    ["detect.gpu.info.use_proprietary"]="Will proceed with proprietary kernel modules."
    ["detect.gpu.warning.unknown_device_id"]="Could not determine Device ID for this GPU. Defaulting to proprietary modules."
    ["detect.gpu.old_gpu_found_warning"]="Detected older NVIDIA GPU that may be incompatible with open kernel modules."
    ["detect.gpu.open_support_prompt"]="You have selected to install open modules (--modules open), but this requires a Turing (RTX 20 series) or newer architecture GPU."
    ["detect.gpu.info.open_support_list"]="Architectures that support open modules: Turing, Ampere, Ada Lovelace, Blackwell"
    ["detect.gpu.info.open_unsupport_list"]="Architectures that require proprietary modules: Maxwell, Pascal, Volta"
    ["detect.gpu.incompatible.solution_prompt"]="We recommend switching to proprietary modules to ensure compatibility."
    ["detect.gpu.incompatible.solution_option1"]="1. (Recommended) Automatically switch to proprietary modules and continue."
    ["detect.gpu.incompatible.solution_option2"]="2. Attempt to use open modules anyway (may cause installation to fail)."
    ["detect.gpu.incompatible.confirm"]="Switch to proprietary kernel modules for installation?"
    ["detect.gpu.incompatible.switch"]="Switched to proprietary kernel modules."
    ["detect.gpu.incompatible.continue_warning"]="Continuing with open kernel modules. If installation fails, please re-run and select proprietary modules."
    ["detect.gpu.incompatible.auto_mode_switch"]="Automation mode: Incompatible GPU detected. Automatically switching to proprietary modules."
    ["detect.gpu.summary.header"]="GPU Detection Summary"
    ["detect.gpu.summary.header.gpu_number"]="GPU #"
    ["detect.gpu.summary.header.architecture"]="Architecture"
    ["detect.gpu.summary.header.module_type"]="Module Type"
    ["detect.gpu.summary.value.open_module"]="Open"
    ["detect.gpu.summary.value.proprietary_module_fallback"]="Proprietary (Fallback)"
    ["detect.gpu.summary.value.proprietary_module"]="Proprietary"
    ["detect.gpu.summary.note.fallback"]="Note: Switched to proprietary modules due to detection of an incompatible GPU."
    ["detect.distro_support.starting"]="Checking OS support..."
    ["detect.distro_support.warning.rhel7_eol"]="RHEL 7 is near End-Of-Life (EOL), support may be limited."
    ["detect.distro_support.error.unsupported_rhel_version"]="Unsupported RHEL/compatible release version:"
    ["detect.distro_support.warning.fedora_unofficial"]="version may require manual adjustments, not officially fully supported."
    ["detect.distro_support.error.fedora_incompatible"]="version is incompatible with official NVIDIA repositories."
    ["detect.distro_support.warning.ubuntu1804_eol"]="Ubuntu 18.04 standard support has ended, support may be limited."
    ["detect.distro_support.warning.ubuntu_maybe_supported"]="This Ubuntu version may be supported, but has not been fully tested by the script:"
    ["detect.distro_support.warning.ubuntu_unspecified"]="Unknown Ubuntu version, will attempt to continue:"
    ["detect.distro_support.warning.debian11_needs_tuning"]="Support for Debian 11 may require manual adjustments."
    ["detect.distro_support.warning.debian_unspecified"]="Unknown Debian version, will attempt to continue:"
    ["detect.distro_support.warning.suse_maybe_supported"]="This SUSE version may be supported, but has not been fully tested by the script:"
    ["detect.distro_support.warning.amzn2_needs_tuning"]="Support for Amazon Linux 2 may require manual adjustments."
    ["detect.distro_support.error.unsupported_amzn_version"]="Unsupported Amazon Linux version:"
    ["detect.distro_support.warning.azure_maybe_supported"]="This Azure Linux version may be supported, but has not been fully tested by the script:"
    ["detect.distro_support.error.unsupported_kylin_version"]="Unsupported KylinOS version."
    ["detect.distro_support.error.unknown_distro"]="Unknown and unsupported distribution:"
    ["detect.distro_support.success.fully_supported"]="Operating system passed compatibility check:"
    ["detect.distro_support.warning.partially_supported"]="Partially supported or untested operating system:"
    ["detect.distro_support.prompt.confirm.continue_install"]="Installation may fail. Do you want to continue?"
    ["detect.distro_support.user_cancelled"]="User cancelled installation after OS compatibility check."
    ["detect.distro_support.error.unsupported"]="This operating system is not supported:"
    ["detect.distro_support.info.supported_list_header"]="The script currently supports the following systems:"
    ["detect.distro_support.prompt.confirm.force_install"]="Do you want to force an installation attempt? (Not recommended)"
    ["detect.distro_support.warning.force_mode_issues"]="Force mode: The installation process may encounter unknown issues."
    ["detect.existing_driver.skipping_check"]="Skipping check for existing drivers."
    ["detect.existing_driver.starting"]="Checking for existing NVIDIA driver installations..."
    ["detect.existing_driver.warning.kernel_module_loaded"]="Detected active NVIDIA kernel module:"
    ["detect.existing_driver.warning.pkg_manager_install"]="Detected NVIDIA drivers installed via package manager:"
    ["detect.existing_driver.warning.runfile_install"]="Detected NVIDIA driver installed via .run file."
    ["detect.existing_driver.warning.ppa_found"]="Detected graphics-drivers PPA source (ppa:graphics-drivers)."
    ["detect.existing_driver.warning.rpm_fusion_found"]="Detected RPM Fusion repository, which may contain NVIDIA drivers."
    ["detect.existing_driver.error.driver_found"]="An existing NVIDIA driver installation was detected on the system."
    ["detect.existing_driver.info.install_method"]="Possible installation method(s):"
    ["detect.existing_driver.prompt.user_choice"]="Suggested Actions:\n1. Uninstall existing driver and reinstall (Recommended)\n2. Force reinstallation (May cause conflicts)\n3. Skip check and continue installation (Advanced users)\n4. Exit installer"
    ["prompt.select_option.please_select"]="Please select an option:"
    ["prompt.select_option.existing_driver.choice_uninstall"]="Automatically uninstall existing drivers and continue (Recommended)"
    ["prompt.select_option.existing_driver.choice_force"]="Force re-installation (overwrite existing drivers)"
    ["prompt.select_option.existing_driver.choice_skip"]="Skip this check and continue (unsafe)"
    ["prompt.select_option.existing_driver.choice_exit"]="Exit script"
    ["detect.existing_driver.warning.force_reinstall_mode"]="Force re-installation mode selected."
    ["detect.existing_driver.warning.skip_mode"]="Skipping checks. Proceed at your own risk."
    ["detect.existing_driver.exit.user_choice"]="User chose to exit due to existing driver."
    ["detect.existing_driver.warning.auto_mode_uninstall"]="Automation mode: Will automatically uninstall existing drivers."
    ["detect.existing_driver.warning.force_mode_skip_uninstall"]="Force mode: Skipping uninstall, will attempt to overwrite."
    ["detect.existing_driver.success.no_driver_found"]="No existing NVIDIA drivers detected."
    ["uninstall.existing_driver.starting"]="Starting uninstallation of existing NVIDIA drivers..."
    ["uninstall.existing_driver.info.using_runfile_uninstaller"]="Using nvidia-uninstall to remove .run file installation..."
    ["uninstall.existing_driver.warning.runfile_uninstall_incomplete"]=".run file driver uninstallation may be incomplete."
    ["uninstall.existing_driver.info.removing_kernel_modules"]="Removing active NVIDIA kernel modules..."
    ["uninstall.existing_driver.warning.module_removal_failed"]="Failed to remove some kernel modules. A reboot may be required."
    ["uninstall.existing_driver.success"]="Existing NVIDIA drivers have been uninstalled."
    ["secure_boot.check.starting"]="Checking Secure Boot status..."
    ["secure_boot.check.method"]="detection method"
    ["secure_boot.check.warning"]="Secure Boot is Enabled"
    ["secure_boot.check.disabled_or_unsupported"]="Secure Boot is disabled or not supported on this system."
    ["secure_boot.enabled.error_detected"]="Secure Boot is detected as enabled on your system."
    ["secure_boot.enabled.why_is_problem"]="Why is this a problem?"
    ["secure_boot.enabled.why_is_problem_detail"]="1. Secure Boot prevents unsigned kernel modules from loading.\n2. The NVIDIA driver contains kernel modules that must be signed to load.\n3. Even if installed successfully, the driver will not work, causing:\n   • Black screens or graphical display issues.\n   • CUDA/OpenCL to be unavailable.\n   • Multi-monitor setups to fail.\n   • The system may not boot."
    ["secure_boot.enabled.solutions"]="Solutions"
    ["secure_boot.enabled.solution.disable"]="Option 1 (Easiest): Disable Secure Boot in your system's UEFI/BIOS settings."
    ["secure_boot.enabled.solution.disable_steps"]="1. Reboot and enter your BIOS/UEFI settings.\n2. Find the 'Security' or 'Boot' options.\n3. Disable the 'Secure Boot' feature.\n4. Save changes and reboot.\n5. Rerun this script."
    ["secure_boot.enabled.solution.sign"]="Option 2 (Recommended): Generate a Machine Owner Key (MOK) and use it to sign the NVIDIA kernel modules."
    ["secure_boot.enabled.solution.sign_steps"]="1. Install necessary tools: mokutil, openssl, dkms.\n2. Generate a Machine Owner Key (MOK).\n3. Enroll the MOK into the UEFI firmware.\n4. Configure DKMS to automatically sign NVIDIA modules.\n5. Rerun this script."
    ["secure_boot.enabled.solution.prebuilt"]="Option 3 (Distro-specific): Use pre-built and signed drivers provided by your distribution."
    ["secure_boot.enabled.solution.prebuilt_steps"]="Some distributions provide pre-signed NVIDIA drivers:\n• Ubuntu: Signed drivers may be available via 'ubuntu-drivers'.\n• RHEL: Pre-compiled signed modules may be available.\n• SUSE: May be available through the official repositories."
    ["secure_boot.enabled.solution.mok_setup"]="MOK Enrollment Process Reminder"
    ["secure_boot.enabled.solution.mok_setup_notice"]="This script can assist with MOK configuration, but it requires you to:\n• Manually confirm the MOK enrollment upon reboot.\n• Remember the password you have set.\n• Understand the security implications of Secure Boot."
    ["secure_boot.enabled.sign.detected"]="Existing MOK key detected. Will attempt to use it for signing."
    ["secure_boot.enabled.advice_footer"]="Please disable Secure Boot or be prepared to sign modules before continuing"
    ["secure_boot.enabled.choose_action.prompt"]="Please select an action:\n1. Exit installer, I will resolve the Secure Boot issue manually.\n2. Help me configure a MOK key (For advanced users).\n3. Force the installation to continue (Not recommended, may lead to system issues)."
    ["secure_boot.enabled.choice.exit"]="Exit the script, I will handle it manually (e.g., disable Secure Boot)."
    ["secure_boot.enabled.choice.sign"]="Attempt to automatically generate and enroll a MOK key for signing (Recommended)."
    ["secure_boot.enabled.choice.force"]="Ignore this warning and continue installation (the driver WILL NOT load!)."
    ["secure_boot.enabled.exit.cancelled_user_fix"]="Script has exited. Please re-run after disabling Secure Boot or preparing for signing."
    ["secure_boot.enabled.exit.useful_commands"]="Useful commands:\n• Check Secure Boot status: mokutil --sb-state\n• List enrolled MOK keys: mokutil --list-enrolled\n• Check for NVIDIA modules: lsmod | grep nvidia"
    ["secure_boot.enabled.exit.user_choice"]="User chose to handle the Secure Boot issue manually."
    ["secure_boot.enabled.warning.user_forced_install"]="User forced to continue installation. The NVIDIA driver will likely FAIL to load after reboot!"
    ["secure_boot.enabled.warning.auto_mode_existing_mok"]="Automation mode: Secure Boot and an existing MOK were detected. Continuing installation."
    ["secure_boot.enabled.error.auto_mode_failure"]="Automation mode failed: Secure Boot is enabled but no MOK is available. Please disable Secure Boot or create a MOK manually."
    ["mok.setup.starting"]="Starting MOK key setup for module signing..."
    ["mok.setup.error.tools_missing"]="Required tools are missing:"
    ["mok.setup.error.please_install_tools"]="Please install them first. For example:"
    ["mok.setup.info.using_ubuntu_key"]="Detected and using existing system MOK key at /var/lib/shim-signed/mok/..."
    ["mok.setup.info.using_dkms_key"]="Detected and using existing DKMS MOK key at /var/lib/dkms/..."
    ["mok.setup.info.generating_new_key"]="No existing MOK key found, generating a new one..."
    ["mok.setup.error.generation_failed"]="MOK key generation failed."
    ["mok.setup.success.generation_complete"]="New MOK key generated and saved in /var/lib/dkms/"
    ["mok.setup.info.enrolling_key"]="Enrolling the MOK key into the system's boot firmware..."
    ["mok.setup.enroll.important_note_header"]="!!! IMPORTANT ACTION: Please set a temporary password !!!"
    ["mok.setup.enroll.note"]="1. You will be prompted to set a one-time password.\n2. Please remember this password, as it is required on reboot.\n3. A simple numeric password is recommended to avoid keyboard layout issues."
    ["mok.setup.error.enroll_failed"]="MOK key enrollment failed. \"mokutil --import\" command failed."
    ["mok.setup.success.enroll_queued"]="MOK key enrollment has been requested."
    ["mok.setup.next_steps.header"]="NEXT STEP: REBOOT and ENROLL KEY"
    ["mok.setup.enroll.next_steps"]="1. After the script finishes, the system will reboot.\n2. The MOK Manager screen will appear during startup.\n3. Select 'Enroll MOK'.\n4. Select 'Continue'.\n5. Select 'Yes'.\n6. Enter the password you set earlier.\n7. The system will reboot again."
    ["mok.setup.next_steps.warning_english_interface"]="NOTE: The MOK management interface is usually in English."
    ["dkms.signing.configuring"]="Configuring DKMS for automatic signing..."
    ["dkms.signing.success"]="DKMS signing configured successfully."
    ["pre_check.starting"]="Performing pre-installation checks..."
    ["root.partition.space.insufficient"]="Root partition has less than 1GB of free space. Installation may fail."
    ["pre_check.warning.vm_detected"]="Detected running inside a virtual machine:"
    ["pre_check.vm.note"]="Important Notes:\n• Ensure 3D acceleration is enabled for the virtual machine.\n• Some virtual machine platforms may not support NVIDIA GPU passthrough.\n• Container environments may require special configuration."
    ["pre_check.warning.custom_kernel_detected"]="Detected custom kernel:"
    ["pre_check.custom_kernel.note"]="Using a custom kernel might require additional configuration for the driver modules to build successfully."
    ["pre_check.success"]="Pre-installation checks completed."
    ["repo.add.exists"]="repository already exists, skipping."
    ["repo.add.adding"]="Adding repository:"
    ["pkg_install.info.installing_missing"]="Installing missing packages:"
    ["pkg_install.info.all_packages_exist"]="All necessary dependency packages are already installed."
    ["repo.enable.already_done"]="Repositories and dependencies already enabled, skipping this step."
    ["repo.enable.starting"]="Enabling third-party repositories and dependencies..."
    ["repo.enable.error.rhel_appstream"]="Failed to enable RHEL AppStream repository."
    ["repo.enable.error.rhel_baseos"]="Failed to enable RHEL BaseOS repository."
    ["repo.enable.error.rhel_crb"]="Failed to enable RHEL CodeReady Builder (CRB) repository."
    ["repo.enable.error.suse_packagehub"]="Failed to enable SUSE PackageHub."
    ["kernel_headers.install.already_done"]="Kernel headers already installed, skipping this step."
    ["kernel_headers.install.starting"]="Installing kernel headers and development packages..."
    ["repo.local.setup.starting"]="Setting up local NVIDIA repository..."
    ["repo.local.setup.downloading"]="Downloading:"
    ["repo.network.setup.starting"]="Setting up network NVIDIA repository..."
    ["repo.network.setup.installing_keyring"]="Downloading and installing NVIDIA GPG keyring..."
    ["repo.network.setup.keyring_exists"]="NVIDIA keyring is already installed."
    ["repo.nvidia.add.already_done"]="NVIDIA repository already added, skipping this step."
    ["repo.nvidia.add.starting"]="Adding official NVIDIA repository..."
    ["dnf_module.enable.starting"]="Enabling DNF module stream..."
    ["nvidia_driver.install.starting"]="Starting NVIDIA driver installation"
    ["nvidia_driver.type.open"]="Open Modules"
    ["nvidia_driver.type.proprietary"]="Proprietary Modules"
    ["nouveau.disable.starting"]="Disabling nouveau driver..."
    ["nouveau.disable.warning.detected_running"]="The nouveau kernel module is currently loaded."
    ["nouveau.disable.warning.processes_using_drm"]="processes may be using DRM device. Attempting to stop the display manager."
    ["nouveau.disable.info.stopping_display_manager"]="Attempting to stop display manager to release nouveau..."
    ["nouveau.disable.info.stop_display_manager"]="Stopping"
    ["nouveau.disable.warning.failed_stopping_display_manager"]="Failed to stop display manager:"
    ["nouveau.disable.info.switching_to_text_mode"]="Switching to multi-user text mode..."
    ["nouveau.disable.info.unloading_module"]="Attempting to unload nouveau kernel module..."
    ["nouveau.disable.info.unload_module"]="Unloading module"
    ["nouveau.disable.success.module_unloaded"]="Module unloaded:"
    ["nouveau.disable.warning.module_unload_failed"]="Failed to unload module:"
    ["nouveau.disable.error.still_running_reboot_needed"]="Could not unload the nouveau module as it is still in use. A reboot is required."
    ["nouveau.disable.success.module_unloaded_all"]="nouveau module successfully unloaded."
    ["nouveau.disable.info.not_running"]="nouveau module is not running."
    ["nouveau.disable.info.creating_blacklist"]="Creating modprobe blacklist file to disable nouveau..."
    ["nouveau.disable.info.updating_initramfs"]="Updating initramfs/initrd image..."
    ["nouveau.disable.warning.initramfs_update_failed"]="Failed to update initramfs."
    ["nouveau.disable.warning.dracut_missing"]="\"dracut\" command not found, cannot update initramfs."
    ["nouveau.disable.info.restarting_display_manager"]="Attempting to restore the display manager..."
    ["nouveau.disable.info.restart_display_manager"]="Restarting"
    ["nouveau.disable.warning.restart_failed"]="restart failed"
    ["nouveau.disable.warning.reboot_required_final"]="A reboot is required to disable nouveau."
    ["nouveau.disable.error.reboot_needed_header"]="!!! REBOOT REQUIRED TO CONTINUE INSTALLATION !!!"
    ["nouveau.disable.error.reboot_needed_note"]="The nouveau driver is still in use. A system reboot is required before NVIDIA driver installation can continue.\nThis usually happens when:\n• A graphical application is using the nouveau driver.\n• The nouveau module is a dependency for another loaded module.\n• The system is currently running in a graphical session."
    ["nouveau.disable.info.auto_mode_reboot"]="Automation mode: The system will now reboot to disable nouveau."
    ["nouveau.disable.confirm.reboot_now"]="Reboot the system now?"
    ["nouveau.disable.info.rebooting_now"]="Rebooting..."
    ["nouveau.disable.exit.user_refused_reboot"]="User refused to reboot. Cannot continue installation."
    ["nouveau.disable.success.continue_install"]="nouveau has been disabled. Continuing with installation."
    ["persistence_daemon.enable.starting"]="Enabling NVIDIA Persistence Daemon..."
    ["persistence_daemon.enable.success"]="NVIDIA Persistence Daemon enabled."
    ["persistence_daemon.enable.warning.service_not_found"]="nvidia-persistenced service not found."
    ["verify.starting"]="Verifying installation..."
    ["verify.success.driver_loaded"]="NVIDIA driver is loaded. Version info:"
    ["verify.warning.module_not_loaded"]="NVIDIA kernel module is not loaded. A reboot may be required."
    ["verify.success.smi_available"]="nvidia-smi command is available."
    ["verify.info.testing_driver"]="Testing driver..."
    ["verify.success.driver_working"]="Driver is working correctly!"
    ["verify.error.smi_failed"]="nvidia-smi command failed to execute. The driver may not be loaded correctly. A reboot is required."
    ["verify.warning.smi_unavailable"]="nvidia-smi command is not available. A reboot may be required."
    ["verify.info.loaded_modules"]="Loaded NVIDIA modules:"
    ["verify.info.module_version"]="Module version:"
    ["common.unknown"]="Unknown"
    ["cleanup.install_files.starting"]="Cleaning up installation files..."
    ["final.success.header"]="🎉 NVIDIA Driver Installed Successfully! 🎉"
    ["final.summary.header"]="Installation Summary"
    ["final.summary.distro"]="Distribution"
    ["final.summary.arch"]="Architecture"
    ["final.summary.module_type"]="Module Type"
    ["module.type.open_kernel"]="Open Kernel Modules"
    ["module.type.proprietary_kernel"]="Proprietary Kernel Modules"
    ["repo.type.local"]="Local"
    ["repo.type.network"]="Network"
    ["final.next_steps.header"]="Next Steps"
    ["final.next_steps.working.note"]="1. ✅ The driver is working correctly. You can start using your NVIDIA GPU now.\n2. To install the CUDA Toolkit, please visit: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/\n3. For technical support, visit the forums: https://forums.developer.nvidia.com/c/gpu-graphics/linux/148\n4. If you encounter issues, you can roll back the installation by running"
    ["final.next_steps.not_working.note"]="1. Reboot the system to ensure the driver is fully loaded.\n2. After rebooting, run 'nvidia-smi' to verify the installation.\n3. To install the CUDA Toolkit, please visit: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/\n4. For technical support, visit the forums: https://forums.developer.nvidia.com/c/gpu-graphics/linux/148\n5. If you encounter issues, you can roll back the installation by running"
    ["final.next_steps.secure_boot.header"]="Secure Boot Note"
    ["final.next_steps.secure_boot.working"]="Your system has Secure Boot enabled, and the driver is working correctly. This indicates that module signing was successful."
    ["final.next_steps.secure_boot.error"]="6. If the MOK Manager screen appears on reboot, select 'Enroll MOK' and enter your password.\n7. If the driver fails to load, check kernel messages with: sudo dmesg | grep nvidia\n8. To verify the module's signature, run: modinfo nvidia | grep sig"
    ["final.notes.compute.header"]="Notes for Compute-Only Installation"
    ["final.notes.compute.notes"]="- This installation does not include desktop graphics components (e.g., OpenGL, Vulkan, X driver).\n- It is intended for compute clusters or headless workstations.\n- To add desktop functionality, you can install the required packages separately later."
    ["final.notes.desktop.header"]="Notes for Desktop-Only Installation"
    ["final.notes.desktop.notes"]="- This installation does not include the CUDA compute components.\n- It is intended for general desktop and gaming purposes.\n- For CUDA support, you can install the 'nvidia-driver-cuda' package later."
    ["permission.error.root_required"]="This script must be run as root. Please use"
    ["main.info.non_interactive_quiet_mode"]="Non-interactive terminal detected. Enabling quiet mode automatically."
    ["main.header.title"]="NVIDIA Driver One-Click Installer"
    ["main.header.auto_mode_subtitle"]="(Automated Installation Mode)"
    ["main.resume.warning_incomplete_state_found"]="Incomplete installation state found. Last completed step:"
    ["main.resume.confirm_resume_install"]="Do you want to attempt to resume the installation from this step? (Selecting 'N' will start over)"
    ["main.resume.info_resuming"]="Resuming installation..."
    ["main.resume.info_restarting"]="Restarting installation from the beginning..."
    ["main.config_summary.header"]="Installation Configuration Summary"
    ["main.config_summary.distro"]="System:"
    ["main.config_summary.module_type"]="Module Type:"
    ["main.config_summary.install_type"]="Install Type:"
    ["main.config_summary.repo_type"]="Repository:"
    ["repo.type.local"]="Local"
    ["repo.type.network"]="Network"
    ["main.config_summary.auto_mode"]="Auto Mode:"
    ["common.yes"]="Yes"
    ["common.no"]="No"
    ["main.config_summary.force_reinstall"]="Force Reinstall:"
    ["main.config_summary.auto_reboot"]="Auto Reboot:"
    ["main.config_summary.confirm"]="Confirm the above configuration and start the installation?"
    ["main.config_summary.user_cancel"]="Installation cancelled by user."
    ["main.install.starting"]="Installation process starting..."
    ["main.reboot_logic.success_no_reboot_needed"]="Installation complete. Driver loaded successfully, no reboot needed!"
    ["main.reboot_logic.success_smi_passed"]="\"nvidia-smi\" verification passed. Your GPU is ready."
    ["main.reboot_logic.info_rebooting_on_user_request"]="Rebooting now as per your request (--auto-reboot)."
    ["main.reboot_logic.info_rebooting_now"]="Rebooting..."
    ["main.reboot_logic.success_auto_mode_no_reboot"]="Automated installation successful, no reboot required."
    ["main.reboot_logic.confirm_optional_reboot"]="Do you want to reboot to ensure all system services are running correctly? (Optional)"
    ["main.reboot_logic.info_reboot_skipped"]="Reboot skipped."
    ["main.reboot_logic.warning_reboot_required"]="Installation complete, but a reboot is required for the driver to take effect."
    ["main.reboot_logic.warning_smi_failed_reboot_required"]="\"nvidia-smi\" verification failed, indicating the driver is not loaded correctly."
    ["main.reboot_logic.reason_nouveau"]="Reason: A reboot is needed to completely disable the nouveau driver."
    ["main.reboot_logic.reason_module_load"]="Reason: A reboot is needed to load the new kernel modules."
    ["main.reboot_logic.info_auto_mode_rebooting"]="Automation mode: System requires a reboot and will proceed now."
    ["main.reboot_logic.confirm_reboot_now"]="Reboot now?"
    ["main.reboot_logic.warning_manual_reboot_needed"]="User chose to reboot later. Please reboot your system manually."
    ["main.reboot_logic.info_verify_after_reboot"]="After rebooting, you can use the \"nvidia-smi\" command to verify that the driver is working correctly."
)
# ================ 语言包结束 ===================

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
        "INT"|"TERM")
            exit 130  # 标准的信号中断退出码
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
        local lock_pid=$(cat "$lock_file" 2>/dev/null)
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
        80) echo "$(gettext "exit_code.pkg_manager.kernel_version_issue")" ;;
        81) echo "$(gettext "exit_code.pkg_manager.dkms_build_failed")" ;;
        82) echo "$(gettext "exit_code.pkg_manager.module_signing_failed")" ;;
        83) echo "$(gettext "exit_code.pkg_manager.driver_validation_failed")" ;;
        90) echo "$(gettext "exit_code.pkg_manager.rollback_file_missing")" ;;
        91) echo "$(gettext "exit_code.pkg_manager.rollback_failed")" ;;
        92) echo "$(gettext "exit_code.state_management.state_file_corrupted")" ;;
        100) echo "$(gettext "exit_code.user_cancelled")" ;;
        *) echo "$(gettext "exit_code.unknown") $code" ;;
    esac
}

# 日志函数
log_info() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
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
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${PURPLE}[STEP]${NC} $1"
    fi
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]] && ! [[ "$QUIET_MODE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

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
# 显示退出码信息
show_exit_codes() {
    cat << 'EOF'
NVIDIA驱动安装脚本 - 退出码说明

═══════════════════════════════════════════════════════════════

退出码分类说明：
• 0      : 成功
• 1-9    : 权限和环境错误
• 10-19  : 硬件检测错误
• 20-29  : 系统兼容性错误
• 30-39  : 参数和配置错误
• 40-49  : Secure Boot相关错误
• 50-59  : 现有驱动冲突
• 60-69  : 网络和下载错误
• 70-79  : 包管理器错误
• 80-89  : 系统状态错误
• 90-99  : 状态管理错误
• 100-109: 用户取消

详细退出码列表：

EOF

    echo "$(gettext "exit_code.permission")"
    for code in 1 2 3; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.hardware")"
    for code in 10 11 12; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.compatibility")"
    for code in 20 21 22; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.config")"
    for code in 30 31 32; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.secure_boot")"
    for code in 40 41 42 43; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.conflict")"
    for code in 50 51 52; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.network")"
    for code in 60 61 62; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.pkg_manager")"
    for code in 70 71 72 73 74; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.system_state")"
    for code in 80 81 82 83; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.state_management")"
    for code in 90 91 92; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    echo "$(gettext "exit_code.user_cancelled")"
    for code in 100; do
        printf "  %-3s - %s\n" "$code" "$(get_exit_code_description $code)"
    done
    echo

    cat << 'EOF'
═══════════════════════════════════════════════════════════════

You can find the last exit code in the file:
    /var/lib/nvidia-installer/last_exit_code
EOF
}

# 预解析函数，只处理需要在脚本早期生效的参数
# This function does not need i18n support as it runs before language selection.
pre_parse_arguments() {
    for arg in "$@"; do
        case "$arg" in
            -y|--yes)
                AUTO_YES=true
                ;;
            -q|--quiet)
                QUIET_MODE=true
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --show-exit-codes)
                show_exit_codes
                exit 0
                ;;
        esac
    done

    # 单独处理 --lang，因为它需要读取下一个参数
    local i=0
    local args=("$@")
    for ((i=0; i<$#; i++)); do
        if [[ "${args[$i]}" == "--lang" ]]; then
            # 确保 --lang 后面有值
            if [[ -n "${args[$((i+1))]}" ]]; then
                LANG_CURRENT="${args[$((i+1))]}"
                export NVIDIA_INSTALLER_LANG="$LANG_CURRENT"
            fi
            break
        fi
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
                INSTALL_TYPE="$2"
                shift 2
                ;;
            -m|--modules)
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
        tac "$ROLLBACK_FILE" | while read -r action; do
            log_info "$(gettext "rollback.info.executing") $action"
            if ! eval "$action"; then
                log_warning "$(gettext "rollback.warning.partial_failure") $action"
                rollback_failed=true
            fi
        done

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

        log_success "$(gettext "detect.os.success") $NAME ($DISTRO_ID $DISTRO_VERSION) [$ARCH]"
    else
        exit_with_code $EXIT_UNSUPPORTED_OS "$(gettext "detect.os.error.cannot_detect")"
    fi
}

# GPU架构检测数据库
# 数据主要来源于 The PCI ID Repository (http://pci-ids.ucw.cz/) 和 NVIDIA 官方文档。
declare -A GPU_ARCH_DB

# 初始化GPU架构数据库
init_gpu_database() {
    # Maxwell架构 (GM1xx, GM2xx) - 需要专有模块
    # GTX 900系列, GTX 700系列部分
    local maxwell_ids=(
        "1380" "1381" "1382" "1390" "1391" "1392" "1393" "1398" "1399"  # GM107
        "13c0" "13c2" "13d7" "13d8" "13d9" "13da" "13f0" "13f1" "13f2" "13f3"  # GM204
        "17c2" "17c8" "17f0" "17f1"  # GM200
        "1340" "1341" "1344" "1346" "1347" "1348" "1349" "134b" "134d" "134e" "134f"  # GM108
    )
    
    # Pascal架构 (GP1xx) - 需要专有模块
    # GTX 10系列, GTX 16系列部分
    local pascal_ids=(
        "15f7" "15f8" "15f9"  # GP100
        "1b00" "1b02" "1b06" "1b30" "1b80" "1b81" "1b82" "1b83" "1b84" "1b87"  # GP102
        "1be0" "1be1" "1c02" "1c03" "1c04" "1c06" "1c07" "1c09" "1c20" "1c21" "1c22" "1c23"  # GP104
        "1c30" "1c31" "1c35" "1c60" "1c61" "1c62" "1c81" "1c82" "1c8c" "1c8d" "1c8f"  # GP106
        "1c90" "1c91" "1c92" "1c94" "1c96" "1cb1" "1cb2" "1cb3" "1cb6" "1cba" "1cbb" "1cbc"  # GP107
        "1d01" "1d10" "1d11" "1d12" "1d13" "1d16" "1d81"  # GP108
    )
    
    # Volta架构 (GV1xx) - 需要专有模块 (主要是Tesla产品)
    local volta_ids=(
        "1db0" "1db1" "1db3" "1db4" "1db5" "1db6" "1db7" "1db8"  # GV100
        "1df0" "1df2" "1df5" "1df6"  # GV100变种
    )
    
    # Turing架构 (TU1xx) - 支持开源模块
    # RTX 20系列, GTX 16系列
    local turing_ids=(
        "1e02" "1e04" "1e07" "1e09" "1e30" "1e36" "1e78" "1e81" "1e82" "1e84" "1e87" "1e89" "1e90" "1e91"  # TU102
        "1f02" "1f03" "1f06" "1f07" "1f08" "1f09" "1f0a" "1f10" "1f11" "1f12" "1f14" "1f15" "1f36" "1f42" "1f47" "1f50" "1f51" "1f54" "1f55" "1f76" "1f82" "1f83" "1f95" "1f96" "1f97" "1f98" "1f99" "1f9c" "1f9d" "1f9f" "1fa0" "1fb0" "1fb1" "1fb2" "1fb6" "1fb7" "1fb8" "1fb9" "1fba" "1fbb" "1fbc" "1fdd"  # TU104/TU106
        "1ff0" "1ff2" "1ff9" "1ffa" "1ffb" "1ffc" "1ffd" "1fff"  # TU117
    )
    
    # Ampere架构 (GA1xx) - 支持开源模块
    # RTX 30系列, RTX A系列
    local ampere_ids=(
        "2204" "2205" "2206" "2207" "2208" "220a" "2216" "2230" "2231" "2232" "2233" "2235" "2236"  # GA102
        "2484" "2486" "2487" "2488" "2489" "248a" "249c" "249d" "24a0" "24b0" "24b1" "24b6" "24b7" "24b8" "24b9" "24ba" "24bb" "24c7" "24c9" "24dc" "24dd" "24e0" "24fa"  # GA104
        "2501" "2503" "2504" "2505" "2507" "2508" "2520" "2521" "2523" "2531" "2544" "2545" "2548" "254b" "2560" "2563" "2571" "2582" "2583" "2584"  # GA106
        "25a0" "25a2" "25a5" "25a6" "25a7" "25a9" "25aa" "25ab" "25ac" "25ad" "25b0" "25b6" "25b8" "25b9" "25ba" "25bb" "25bc" "25bd" "25e0" "25e2" "25e5" "25f9" "25fa" "25fb" "25fc"  # GA107
    )
    
    # Ada Lovelace架构 (AD1xx) - 支持开源模块
    # RTX 40系列
    local ada_ids=(
        "2684" "2685" "2688" "2689" "268a" "268b" "268e" "268f"  # AD102
        "2704" "2705" "2706" "2708" "2709" "270a" "270b" "270d" "270f" "2717" "2718" "2730" "2757" "2760"  # AD104
        "2803" "2805" "2820" "2838" "2860" "2882" "2887" "2888"  # AD106
        "28a0" "28a1" "28b0" "28b8" "28b9" "28ba" "28bb" "28bc" "28e0" "28e1"  # AD107
    )
    
    # Blackwell架构 (GB1xx) - 支持开源模块 (最新架构)
    local blackwell_ids=(
        "2330" "2331" "2335" "233a" "233d" "2342"  # GB202 (RTX 50系列预期)
        "2770" "2782"  # GB100 (数据中心)
    )
    
    # 填充数据库
    for id in "${maxwell_ids[@]}"; do
        GPU_ARCH_DB["$id"]="Maxwell"
    done
    
    for id in "${pascal_ids[@]}"; do
        GPU_ARCH_DB["$id"]="Pascal"
    done
    
    for id in "${volta_ids[@]}"; do
        GPU_ARCH_DB["$id"]="Volta"
    done
    
    for id in "${turing_ids[@]}"; do
        GPU_ARCH_DB["$id"]="Turing"
    done
    
    for id in "${ampere_ids[@]}"; do
        GPU_ARCH_DB["$id"]="Ampere"
    done
    
    for id in "${ada_ids[@]}"; do
        GPU_ARCH_DB["$id"]="Ada Lovelace"
    done
    
    for id in "${blackwell_ids[@]}"; do
        GPU_ARCH_DB["$id"]="Blackwell"
    done
}

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
        "Turing"|"Ampere"|"Ada Lovelace"|"Blackwell")
            return 0  # 支持开源模块
            ;;
        "Maxwell"|"Pascal"|"Volta")
            return 1  # 需要专有模块
            ;;
        *)
            return 1  # 未知架构，保守选择专有模块
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
            local device_id=$(lspci -s "$pci_address" -nn | grep -oP '10de:\K[0-9a-fA-F]{4}' | tr '[:lower:]' '[:upper:]')
            
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

# 智能发行版版本检查
check_distro_support() {
    log_step "$(gettext "detect.distro_support.starting")"

    local is_supported=true
    local support_level="full"  # full, partial, unsupported
    local warning_msg=""
    
    case $DISTRO_ID in
        rhel|rocky|ol|almalinux)
            case $DISTRO_VERSION in
                8|9|10) support_level="full" ;;
                7) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.rhel7_eol")" ;;
                *) support_level="unsupported"; warning_msg="$(gettext "detect.distro_support.error.unsupported_rhel_version") $DISTRO_VERSION" ;;
            esac
            ;;
        fedora)
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
            ;;
        ubuntu)
            case $DISTRO_VERSION in
                20.04|22.04|24.04) support_level="full" ;;
                18.04) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.ubuntu1804_eol")" ;;
                *) 
                    # 尝试从codename判断
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
            ;;
        debian)
            case $DISTRO_VERSION in
                12) support_level="full" ;;
                11) support_level="partial"; warning_msg=$(gettext "detect.distro_support.warning.debian11_needs_tuning") ;;
                *) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.debian_unspecified") $DISTRO_VERSION" ;;
            esac
            ;;
        opensuse*|sles)
            if [[ "$DISTRO_VERSION" =~ ^15 ]]; then
                support_level="full"
            else
                support_level="partial"
                warning_msg="$(gettext "detect.distro_support.warning.suse_maybe_supported") $DISTRO_VERSION"
            fi
            ;;
        amzn)
            case $DISTRO_VERSION in
                2023) support_level="full" ;;
                2) support_level="partial"; warning_msg=$(gettext "detect.distro_support.warning.amzn2_needs_tuning") ;;
                *) support_level="unsupported"; warning_msg="$(gettext "detect.distro_support.error.unsupported_amzn_version") $DISTRO_VERSION" ;;
            esac
            ;;
        azurelinux|mariner)
            case $DISTRO_VERSION in
                2.0|3.0) support_level="full" ;;
                *) support_level="partial"; warning_msg="$(gettext "detect.distro_support.warning.azure_maybe_supported") $DISTRO_VERSION" ;;
            esac
            ;;
        kylin)
            case $DISTRO_VERSION in
                10) support_level="full" ;;
                *) support_level="unsupported"; warning_msg=$(gettext "detect.distro_support.error.unsupported_kylin_version") ;;
            esac
            ;;
        *)
            support_level="unsupported"
            warning_msg="$(gettext "detect.distro_support.error.unknown_distro") $DISTRO_ID"
            ;;
    esac
    
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
    
    # 检查包管理器安装的驱动
    case $DISTRO_ID in
        ubuntu|debian)
            if dpkg -l | grep -q nvidia-driver; then
                existing_driver="package_manager"
                installation_method="apt/dpkg"
                log_warning "$(gettext "detect.existing_driver.warning.pkg_manager_install")"
                dpkg -l | grep nvidia-driver
            fi
            ;;
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            if rpm -qa | grep -q nvidia-driver; then
                existing_driver="package_manager"
                installation_method="dnf/rpm"
                log_warning "$(gettext "detect.existing_driver.warning.pkg_manager_install")"
                rpm -qa | grep nvidia
            fi
            ;;
        opensuse*|sles)
            if zypper search -i | grep -q nvidia; then
                existing_driver="package_manager"
                installation_method="zypper"
                log_warning "$(gettext "detect.existing_driver.warning.pkg_manager_install")"
                zypper search -i | grep nvidia
            fi
            ;;
    esac
    
    # 检查runfile安装
    if [[ -f /usr/bin/nvidia-uninstall ]]; then
        existing_driver="runfile"
        installation_method="runfile"
        log_warning "$(gettext "detect.existing_driver.warning.runfile_install")"
    fi
    
    # 检查其他PPA或第三方源
    case $DISTRO_ID in
        ubuntu)
            if apt-cache policy | grep -q "graphics-drivers"; then
                log_warning "$(gettext "detect.existing_driver.warning.ppa_found")"
                installation_method="${installation_method:+$installation_method, }graphics-drivers PPA"
            fi
            ;;
        fedora)
            if dnf repolist | grep -q rpmfusion; then
                log_warning "$(gettext "detect.existing_driver.warning.rpm_fusion_found")"
                installation_method="${installation_method:+$installation_method, }RPM Fusion"
            fi
            ;;
    esac
    
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
            case $DISTRO_ID in
                ubuntu|debian)
                    apt remove --purge -y nvidia-* libnvidia-* || true
                    apt autoremove -y || true
                    ;;
                rhel|rocky|ol|almalinux|fedora|kylin|amzn)
                    if dnf --version &>/dev/null; then
                        dnf remove -y nvidia-* libnvidia-* || true
                        dnf autoremove -y || true
                    else
                        yum remove -y nvidia-* libnvidia-* || true
                    fi
                    ;;
                opensuse*|sles)
                    zypper remove -y nvidia-* || true
                    ;;
            esac
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
        if [[ -f /sys/firmware/efi/efivars/SecureBoot-* ]]; then
            local secure_boot_value=$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | tr -d ' ')
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

    log_info "$(gettext "配置DKMS自动签名...")"

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

    log_success "$(gettext "dkms.signing.configuring")"
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

# 获取发行版特定的变量
get_distro_vars() {
    case $DISTRO_ID in
        rhel|rocky|ol|almalinux)
            if [[ "$DISTRO_VERSION" == "10" ]]; then
                DISTRO_REPO="rhel10"
            elif [[ "$DISTRO_VERSION" == "9" ]]; then
                DISTRO_REPO="rhel9"
            elif [[ "$DISTRO_VERSION" == "8" ]]; then
                DISTRO_REPO="rhel8"
            fi
            ARCH_EXT="x86_64"
            ;;
        fedora)
            DISTRO_REPO="fedora${DISTRO_VERSION}"
            ARCH_EXT="x86_64"
            ;;
        ubuntu)
            DISTRO_REPO="ubuntu${DISTRO_VERSION//.}"
            ARCH_EXT="amd64"
            ;;
        debian)
            DISTRO_REPO="debian${DISTRO_VERSION}"
            ARCH_EXT="amd64"
            ;;
        opensuse*)
            DISTRO_REPO="opensuse15"
            ARCH_EXT="x86_64"
            ;;
        sles)
            DISTRO_REPO="sles15"
            ARCH_EXT="x86_64"
            ;;
        amzn)
            DISTRO_REPO="amzn2023"
            ARCH_EXT="x86_64"
            ;;
        azurelinux)
            DISTRO_REPO="azl3"
            ARCH_EXT="x86_64"
            ;;
        mariner)
            DISTRO_REPO="cm2"
            ARCH_EXT="x86_64"
            ;;
        kylin)
            DISTRO_REPO="kylin10"
            ARCH_EXT="x86_64"
            ;;
    esac
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

# 启用第三方仓库和依赖
enable_repositories() {
    if is_step_completed "enable_repositories"; then
        log_info "$(gettext "repo.enable.already_done")"
        return 0
    fi
    
    log_step "$(gettext "repo.enable.starting")"
    
    case $DISTRO_ID in
        rhel)
            # RHEL需要subscription-manager启用仓库
            if [[ "$DISTRO_VERSION" == "10" ]]; then
                subscription-manager repos --enable=rhel-10-for-${ARCH}-appstream-rpms || log_warning "$(gettext "repo.enable.error.rhel_appstream")"
                subscription-manager repos --enable=rhel-10-for-${ARCH}-baseos-rpms || log_warning "$(gettext "repo.enable.error.rhel_baseos")"
                subscription-manager repos --enable=codeready-builder-for-rhel-10-${ARCH}-rpms || log_warning "$(gettext "repo.enable.error.rhel_crb")"

                # 安装EPEL
                if ! rpm -q epel-release &>/dev/null; then
                    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
                    save_rollback_info "dnf remove -y epel-release"
                fi
            elif [[ "$DISTRO_VERSION" == "9" ]]; then
                subscription-manager repos --enable=rhel-9-for-${ARCH}-appstream-rpms || log_warning "$(gettext "repo.enable.error.rhel_appstream")"
                subscription-manager repos --enable=rhel-9-for-${ARCH}-baseos-rpms || log_warning "$(gettext "repo.enable.error.rhel_baseos")"
                subscription-manager repos --enable=codeready-builder-for-rhel-9-${ARCH}-rpms || log_warning "$(gettext "repo.enable.error.rhel_crb")"
                if ! rpm -q epel-release &>/dev/null; then
                    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
                    save_rollback_info "dnf remove -y epel-release"
                fi
            elif [[ "$DISTRO_VERSION" == "8" ]]; then
                subscription-manager repos --enable=rhel-8-for-${ARCH}-appstream-rpms || log_warning "$(gettext "repo.enable.error.rhel_appstream")"
                subscription-manager repos --enable=rhel-8-for-${ARCH}-baseos-rpms || log_warning "$(gettext "repo.enable.error.rhel_baseos")"
                subscription-manager repos --enable=codeready-builder-for-rhel-8-${ARCH}-rpms || log_warning "$(gettext "repo.enable.error.rhel_crb")"
                if ! rpm -q epel-release &>/dev/null; then
                    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
                    save_rollback_info "dnf remove -y epel-release"
                fi
            fi
            ;;
        rocky)
            if [[ "$DISTRO_VERSION" =~ ^(9|10) ]]; then
                if ! dnf repolist enabled | grep -q crb; then
                    dnf config-manager --set-enabled crb
                    save_rollback_info "dnf config-manager --set-disabled crb"
                fi
                safe_install_package "dnf" epel-release
            elif [[ "$DISTRO_VERSION" == "8" ]]; then
                if ! dnf repolist enabled | grep -q powertools; then
                    dnf config-manager --set-enabled powertools
                    save_rollback_info "dnf config-manager --set-disabled powertools"
                fi
                safe_install_package "dnf" epel-release
            fi
            ;;
        ol)
            if [[ "$DISTRO_VERSION" == "10" ]]; then
                if ! dnf repolist enabled | grep -q ol10_codeready_builder; then
                    dnf config-manager --set-enabled ol10_codeready_builder
                    save_rollback_info "dnf config-manager --set-disabled ol10_codeready_builder"
                fi
                safe_install_package "dnf" oracle-epel-release-el10
            elif [[ "$DISTRO_VERSION" == "9" ]]; then
                if ! dnf repolist enabled | grep -q ol9_codeready_builder; then
                    dnf config-manager --set-enabled ol9_codeready_builder
                    save_rollback_info "dnf config-manager --set-disabled ol9_codeready_builder"
                fi
                safe_install_package "dnf" oracle-epel-release-el9
            elif [[ "$DISTRO_VERSION" == "8" ]]; then
                if ! dnf repolist enabled | grep -q ol8_codeready_builder; then
                    dnf config-manager --set-enabled ol8_codeready_builder
                    save_rollback_info "dnf config-manager --set-disabled ol8_codeready_builder"
                fi
                safe_install_package "dnf" oracle-epel-release-el8
            fi
            ;;
        debian)
            # 启用contrib仓库
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
            ;;
        opensuse*|sles)
            # 启用PackageHub
            if command -v SUSEConnect >/dev/null 2>&1 && ! SUSEConnect -l | grep -q PackageHub; then
                SUSEConnect --product PackageHub/15/$(uname -m) || log_warning "$(gettext "repo.enable.error.suse_packagehub")"
                save_rollback_info "SUSEConnect -d --product PackageHub/15/$(uname -m)"
            fi
            
            if ! is_step_completed "zypper_refresh_after_packagehub"; then
                zypper refresh
                save_state "zypper_refresh_after_packagehub"
            fi
            ;;
        azurelinux)
            safe_install_package "tdnf" azurelinux-repos-extended
            ;;
        mariner)
            safe_install_package "tdnf" mariner-repos-extended
            ;;
    esac
    
    save_state "enable_repositories"
}

# 安装内核头文件和开发包
install_kernel_headers() {
    if is_step_completed "install_kernel_headers"; then
        log_info "$(gettext "kernel_headers.install.already_done")"
        return 0
    fi

    log_step "$(gettext "kernel_headers.install.starting")"

    local kernel_version=$(uname -r)
    
    case $DISTRO_ID in
        rhel|rocky|ol|almalinux)
            if [[ "$DISTRO_VERSION" =~ ^(9|10) ]]; then
                safe_install_package "dnf" kernel-devel-matched kernel-headers
            else
                safe_install_package "dnf" "kernel-devel-$(uname -r)" kernel-headers
            fi
            ;;
        fedora)
            safe_install_package "dnf" kernel-devel-matched kernel-headers
            ;;
        ubuntu|debian)
            if ! is_step_completed "apt_update_before_headers"; then
                apt update
                save_state "apt_update_before_headers"
            fi
            safe_install_package "apt" "linux-headers-$(uname -r)"
            ;;
        opensuse*|sles)
            local variant=$(uname -r | grep -o '\-[^-]*' | sed 's/^-//')
            local version=$(uname -r | sed 's/\-[^-]*$//')
            safe_install_package "zypper" "kernel-${variant:-default}-devel=${version}"
            ;;
        amzn)
            safe_install_package "dnf" "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)"
            ;;
        azurelinux|mariner)
            safe_install_package "tdnf" "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" "kernel-modules-extra-$(uname -r)"
            ;;
        kylin)
            safe_install_package "dnf" "kernel-devel-$(uname -r)" kernel-headers
            ;;
    esac
    
    save_state "install_kernel_headers"
}

# 安装本地仓库
install_local_repository() {
    log_info "$(gettext "repo.local.setup.starting")"

    local version=${DRIVER_VERSION:-"latest"}
    local base_url="https://developer.download.nvidia.cn/compute/nvidia-driver"
    
    case $DISTRO_ID in
        rhel|rocky|ol|almalinux|fedora|amzn|azurelinux|mariner|kylin)
            local rpm_file="nvidia-driver-local-repo-${DISTRO_REPO}.${version}.${ARCH_EXT}.rpm"
            log_info "$(gettext "repo.local.setup.downloading") $rpm_file"
            wget -O /tmp/$rpm_file "${base_url}/${version}/local_installers/${rpm_file}"
            rpm --install /tmp/$rpm_file
            ;;
        ubuntu|debian)
            local deb_file="nvidia-driver-local-repo-${DISTRO_REPO}-${version}_${ARCH_EXT}.deb"
            log_info "$(gettext "repo.local.setup.downloading") $deb_file"
            wget -O /tmp/$deb_file "${base_url}/${version}/local_installers/${deb_file}"
            dpkg -i /tmp/$deb_file
            apt update
            # 添加GPG密钥
            cp /var/nvidia-driver-local-repo-${DISTRO_REPO}-${version}/nvidia-driver-*-keyring.gpg /usr/share/keyrings/
            ;;
        opensuse*|sles)
            local rpm_file="nvidia-driver-local-repo-${DISTRO_REPO}.${version}.${ARCH_EXT}.rpm"
            log_info "$(gettext "repo.local.setup.downloading") $rpm_file"
            wget -O /tmp/$rpm_file "${base_url}/${version}/local_installers/${rpm_file}"
            rpm --install /tmp/$rpm_file
            ;;
    esac
}

# 安装网络仓库 
install_network_repository() {
    log_info "$(gettext "repo.network.setup.starting")"

    case $DISTRO_ID in
        rhel|rocky|ol|almalinux|fedora|amzn|kylin)
            local repo_url="https://developer.download.nvidia.cn/compute/cuda/repos/${DISTRO_REPO}/${ARCH}/cuda-${DISTRO_REPO}.repo"
            safe_add_repository "dnf" "$repo_url" "cuda-${DISTRO_REPO}"
            
            # 清理缓存
            if ! is_step_completed "dnf_cache_cleared"; then
                dnf clean expire-cache
                save_state "dnf_cache_cleared"
            fi
            ;;
        ubuntu|debian)
            # 检查并安装cuda-keyring
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
            ;;
        opensuse*|sles)
            local repo_url="https://developer.download.nvidia.cn/compute/cuda/repos/${DISTRO_REPO}/${ARCH}/cuda-${DISTRO_REPO}.repo"
            safe_add_repository "zypper" "$repo_url" "cuda-${DISTRO_REPO}"
            
            if ! is_step_completed "zypper_refresh_after_repo"; then
                zypper refresh
                save_state "zypper_refresh_after_repo"
            fi
            ;;
        azurelinux|mariner)
            local repo_url="https://developer.download.nvidia.cn/compute/cuda/repos/${DISTRO_REPO}/${ARCH}/cuda-${DISTRO_REPO}.repo"
            safe_add_repository "dnf" "$repo_url" "cuda-${DISTRO_REPO}"
            
            if ! is_step_completed "tdnf_cache_cleared"; then
                tdnf clean expire-cache
                save_state "tdnf_cache_cleared"
            fi
            ;;
    esac
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
install_nvidia_driver() {
    log_step "$(gettext "nvidia_driver.install.starting") ($(if $USE_OPEN_MODULES; then echo $(gettext "nvidia_driver.type.open"); else echo $(gettext "nvidia_driver.type.proprietary"); fi), $INSTALL_TYPE)..."

    case $DISTRO_ID in
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            install_nvidia_rpm
            ;;
        ubuntu|debian)
            install_nvidia_deb
            ;;
        opensuse*|sles)
            install_nvidia_suse
            ;;
        azurelinux|mariner)
            # Azure Linux只支持开源模块
            tdnf install -y nvidia-open
            ;;
    esac
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
    
    # 更新initramfs
    log_info "$(gettext "nouveau.disable.info.updating_initramfs")"
    case $DISTRO_ID in
        ubuntu|debian)
            if ! update-initramfs -u; then
                log_warning "$(gettext "nouveau.disable.warning.initramfs_update_failed")"
            fi
            ;;
        rhel|rocky|ol|almalinux|fedora|kylin|amzn)
            if command -v dracut &> /dev/null; then
                if ! dracut -f; then
                    log_warning "$(gettext "nouveau.disable.warning.initramfs_update_failed")"
                fi
            else
                log_warning "$(gettext "nouveau.disable.warning.dracut_missing")"
            fi
            ;;
        opensuse*|sles)
            if ! mkinitrd; then
                log_warning "$(gettext "nouveau.disable.warning.initramfs_update_failed")"
            fi
            ;;
        azurelinux|mariner)
            if command -v dracut &> /dev/null; then
                if ! dracut -f; then
                    log_warning "$(gettext "nouveau.disable.warning.initramfs_update_failed")"
                fi
            else
                log_warning "$(gettext "nouveau.disable.warning.dracut_missing")"
            fi
            ;;
    esac
    
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
        log_success "$(gettext "verify.driver_loaded"): $driver_version"
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
        case $DISTRO_ID in
            rhel|rocky|ol|almalinux|fedora|kylin|amzn)
                dnf remove -y nvidia-driver-local-repo-* 2>/dev/null || true
                ;;
            ubuntu|debian)
                apt remove --purge -y nvidia-driver-local-repo-* 2>/dev/null || true
                ;;
            opensuse*|sles)
                zypper remove -y nvidia-driver-local-repo-* 2>/dev/null || true
                ;;
            azurelinux|mariner)
                tdnf remove -y nvidia-driver-local-repo-* 2>/dev/null || true
                ;;
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
    if [[ -d /sys/firmware/efi/efivars ]] && [[ -f /sys/firmware/efi/efivars/SecureBoot-* ]]; then
        local sb_value=$(od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | tr -d ' ')
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
    
    # 创建状态目录
    create_state_dir
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 检查root权限
    check_root
    
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
        echo "- $(gettext "main.config_summary.module_type") $(if $USE_OPEN_MODULES; then echo $(gettext "module.type.open_kernel"); else echo $(gettext "module.type.proprietary"); fi)"
        echo "- $(gettext "main.config_summary.install_type") $INSTALL_TYPE"
        echo "- $(gettext "main.config_summary.repo_type") $(if $USE_LOCAL_REPO; then echo $(gettext "repository.type.local"); else echo $(gettext "repository.type.remote"); fi)"
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
        
        if [[ "$AUTO_YES" == "true" ]] || [[ "$REBOOT_AFTER_INSTALL" == "true" ]]; then
            log_info "$(gettext "main.reboot_logic.info_auto_mode_rebooting")"
            rm -f "$STATE_FILE" "$ROLLBACK_FILE" "$STATE_DIR/nouveau_status" "$STATE_DIR/driver_status"
            cleanup_lock_files
            reboot
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
