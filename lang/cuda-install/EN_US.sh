declare -A LANG_PACK_EN_US

LANG_PACK_EN_US=(
    # General
    ["prompt.confirm.yes_or_no"]="(y/N)"
    ["prompt.confirm.auto_yes"]="[Auto-confirm] Skipping confirmation prompt"

    # Logging
    ["log.starting"]="Starting CUDA Toolkit installation script"
    ["log.root_check"]="Checking root privileges"
    ["log.root_check.fail"]="This script must be run as root. Please retry with sudo."
    ["log.detect_os"]="Detecting operating system..."
    ["log.detect_os.success"]="Detected operating system:"
    ["log.detect_os.fail"]="Cannot determine OS release information. Please ensure /etc/os-release or /usr/lib/os-release exists."
    ["log.detect_arch"]="Detected architecture:"
    ["log.detect_pm"]="Detecting package manager..."
    ["log.detect_pm.result"]="Using package manager:"
    ["log.repo_url"]="Using repository URL:"
    ["log.preinstall"]="Performing pre-installation steps..."
    ["log.preinstall.none"]="No pre-installation steps required"
    ["log.addrepo"]="Adding CUDA Toolkit repository..."
    ["log.addrepo.none"]="No repository addition required"
    ["log.install_cuda"]="Installing CUDA Toolkit..."
    ["log.install_cuda.version"]="Installing CUDA version:"
    ["log.install_cuda.auto"]="Auto-installing latest CUDA"
    ["log.install_cuda.select"]="No CUDA version specified, entering interactive selection"
    ["log.install_cuda.skip"]="Skipping CUDA Toolkit installation per configuration"
    ["log.install_ctk"]="Installing NVIDIA Container Toolkit..."
    ["log.install_ctk.skip"]="Skipping Container Toolkit installation per configuration"
    ["log.install_pkg"]="Installing package(s):"
    ["log.query_pkg"]="Querying package:"

    # GPU detection
    ["gpu.check.starting"]="Detecting NVIDIA GPU..."
    ["gpu.check.found"]="NVIDIA GPU detected"
    ["gpu.check.not_found"]="No NVIDIA GPU detected. CUDA can be installed without GPU for development, but GPU computation will not work."
    ["gpu.check.lspci_missing"]="lspci command not available, skipping GPU detection"

    # Version selection
    ["select.cuda_version.header"]="Available CUDA versions:"
    ["select.cuda_version.no_versions"]="No available CUDA versions found in the repository."

    # Confirmation
    ["confirm.install.header"]="Installation Configuration Summary"
    ["confirm.install.distro"]="Operating System"
    ["confirm.install.arch"]="Architecture"
    ["confirm.install.type"]="Install Type"
    ["confirm.install.cuda_version"]="CUDA Version"
    ["confirm.install.repo_url"]="Repository URL"
    ["confirm.install.proceed"]="Proceed with installation?"

    # State management
    ["state.dir.create_failed"]="Failed to create state directory:"
    ["state.lock.another_running"]="Another installation process is running (PID:"
    ["state.lock.cleaning_orphaned"]="Cleaning orphaned lock file"
    ["state.lock.created"]="Install lock created:"
    ["state.step.already_done"]="Step already completed, skipping:"

    # Signal handling
    ["signal.interrupted"]="Script interrupted by signal:"
    ["signal.state_saved"]="Installation state saved, execution can be resumed"
    ["signal.cleaning_temp"]="Cleaning up temporary files..."
    ["signal.release_lock"]="Releasing lock file:"

    # Rollback
    ["rollback.starting"]="Starting rollback..."
    ["rollback.file_missing"]="Rollback information file not found:"
    ["rollback.confirm"]="Proceed with rollback?"
    ["rollback.executing"]="Executing rollback action:"
    ["rollback.partial_failure"]="Rollback action partially failed:"
    ["rollback.success"]="Rollback completed"
    ["rollback.user_cancelled"]="User cancelled rollback"
    ["rollback.warning"]="The following changes will be undone:"

    # Cleanup
    ["cleanup.starting"]="Cleaning up installation state..."
    ["cleanup.state_found"]="Previous installation state found"
    ["cleanup.confirm"]="Clean up installation state?"
    ["cleanup.done"]="Installation state cleaned up"
    ["cleanup.no_state"]="No installation state found"

    # Exit codes
    ["exit_code.success"]="Success"
    ["exit_code.no_root"]="Root privileges required"
    ["exit_code.state_dir_failed"]="Failed to create state directory"
    ["exit_code.unsupported_os"]="Unsupported operating system"
    ["exit_code.unsupported_arch"]="Unsupported architecture"
    ["exit_code.invalid_args"]="Invalid command-line arguments"
    ["exit_code.invalid_install_type"]="Invalid installation type"
    ["exit_code.network_failed"]="Network connection failed"
    ["exit_code.repo_add_failed"]="Failed to add repository"
    ["exit_code.pkg_install_failed"]="Package installation failed"
    ["exit_code.rollback_file_missing"]="Rollback information file not found"
    ["exit_code.rollback_failed"]="Rollback operation failed"
    ["exit_code.state_file_corrupted"]="State file corrupted"
    ["exit_code.user_cancelled"]="User cancelled"
    ["exit_code.unknown_code"]="Unknown exit code"

    # Final
    ["final.success"]="CUDA Toolkit installation completed!"
)
