declare -A LANG_PACK_ZH_CN

LANG_PACK_ZH_CN=(
    # 通用
    ["prompt.confirm.yes_or_no"]="(y/N)"
    ["prompt.confirm.auto_yes"]="[自动确认] 跳过确认提示"

    # 日志
    ["log.starting"]="开始执行 CUDA Toolkit 安装脚本"
    ["log.root_check"]="检查 root 权限"
    ["log.root_check.fail"]="此脚本需要 root 权限运行，请使用 sudo 重试。"
    ["log.detect_os"]="正在检测操作系统..."
    ["log.detect_os.success"]="检测到操作系统:"
    ["log.detect_os.fail"]="无法确定操作系统信息。请确保 /etc/os-release 或 /usr/lib/os-release 存在。"
    ["log.detect_arch"]="检测到架构:"
    ["log.detect_pm"]="正在检测包管理器..."
    ["log.detect_pm.result"]="使用包管理器:"
    ["log.repo_url"]="使用仓库地址:"
    ["log.preinstall"]="正在执行预安装步骤..."
    ["log.preinstall.none"]="无需预安装步骤"
    ["log.addrepo"]="正在添加 CUDA Toolkit 仓库..."
    ["log.addrepo.none"]="无需添加仓库"
    ["log.install_cuda"]="正在安装 CUDA Toolkit..."
    ["log.install_cuda.version"]="安装 CUDA 版本:"
    ["log.install_cuda.auto"]="自动安装最新版 CUDA"
    ["log.install_cuda.select"]="未指定 CUDA 版本，进入交互选择"
    ["log.install_cuda.skip"]="按配置跳过 CUDA Toolkit 安装"
    ["log.install_ctk"]="正在安装 NVIDIA Container Toolkit..."
    ["log.install_ctk.skip"]="按配置跳过 Container Toolkit 安装"
    ["log.install_pkg"]="正在安装软件包:"
    ["log.query_pkg"]="正在查询软件包:"

    # GPU 检测
    ["gpu.check.starting"]="正在检测 NVIDIA GPU..."
    ["gpu.check.found"]="检测到 NVIDIA GPU"
    ["gpu.check.not_found"]="未检测到 NVIDIA GPU。CUDA 可在无 GPU 环境下安装用于开发，但无法运行 GPU 计算。"
    ["gpu.check.lspci_missing"]="lspci 命令不可用，跳过 GPU 检测"

    # 版本选择
    ["select.cuda_version.header"]="可用的 CUDA 版本:"
    ["select.cuda_version.no_versions"]="仓库中未找到可用的 CUDA 版本。"

    # 确认
    ["confirm.install.header"]="安装配置摘要"
    ["confirm.install.distro"]="操作系统"
    ["confirm.install.arch"]="架构"
    ["confirm.install.type"]="安装类型"
    ["confirm.install.cuda_version"]="CUDA 版本"
    ["confirm.install.repo_url"]="仓库地址"
    ["confirm.install.proceed"]="是否继续安装?"

    # 状态管理
    ["state.dir.create_failed"]="无法创建状态目录:"
    ["state.lock.another_running"]="另一个安装进程正在运行 (PID:"
    ["state.lock.cleaning_orphaned"]="清理残留锁文件"
    ["state.lock.created"]="已创建安装锁:"
    ["state.step.already_done"]="步骤已完成，跳过:"

    # 信号处理
    ["signal.interrupted"]="脚本被信号中断:"
    ["signal.state_saved"]="安装状态已保存，可恢复执行"
    ["signal.cleaning_temp"]="正在清理临时文件..."
    ["signal.release_lock"]="释放锁文件:"

    # 回滚
    ["rollback.starting"]="正在执行回滚..."
    ["rollback.file_missing"]="回滚信息文件不存在:"
    ["rollback.confirm"]="是否继续回滚?"
    ["rollback.executing"]="正在执行回滚操作:"
    ["rollback.partial_failure"]="回滚操作部分失败:"
    ["rollback.success"]="回滚完成"
    ["rollback.user_cancelled"]="用户取消回滚"
    ["rollback.warning"]="以下更改将被撤销："

    # 清理
    ["cleanup.starting"]="正在清理安装状态..."
    ["cleanup.state_found"]="发现上次安装状态"
    ["cleanup.confirm"]="是否清理安装状态?"
    ["cleanup.done"]="安装状态已清理"
    ["cleanup.no_state"]="未发现安装状态"

    # 退出码
    ["exit_code.success"]="成功"
    ["exit_code.no_root"]="需要 root 权限"
    ["exit_code.state_dir_failed"]="无法创建状态目录"
    ["exit_code.unsupported_os"]="不支持的操作系统"
    ["exit_code.unsupported_arch"]="不支持的架构"
    ["exit_code.invalid_args"]="无效的命令行参数"
    ["exit_code.invalid_install_type"]="无效的安装类型"
    ["exit_code.network_failed"]="网络连接失败"
    ["exit_code.repo_add_failed"]="添加仓库失败"
    ["exit_code.pkg_install_failed"]="软件包安装失败"
    ["exit_code.rollback_file_missing"]="回滚信息文件不存在"
    ["exit_code.rollback_failed"]="回滚操作失败"
    ["exit_code.state_file_corrupted"]="状态文件损坏"
    ["exit_code.user_cancelled"]="用户取消"
    ["exit_code.unknown_code"]="未知退出码"

    # 完成
    ["final.success"]="CUDA Toolkit 安装完成!"
    ["final.summary.header"]="安装摘要"
)
