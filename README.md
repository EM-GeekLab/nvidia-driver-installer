<p align="center">
    <a href="https://github.com/EM-GeekLab/nvidia-driver-installer">
        <img src="./logo.svg" alt="NVIDIA Driver Installer" width="150">
    </a>
</p>
<h1 align="center">NVIDIA 驱动通用安装脚本</h1>
<p align="center">一个脚本，支持多种 Linux 发行版的自动化 NVIDIA 驱动安装</p>

```bash
curl -sSL https://raw.githubusercontent.com/EM-GeekLab/nvidia-driver-installer/main/nvidia-install.sh -o nvidia-install.sh
sudo bash nvidia-install.sh
```

<p align="center">
    简体中文 | <a href="README.en.md">English</a>
</p>
<p align="center">
  <a href="https://github.com/EM-GeekLab/nvidia-driver-installer/blob/main/LICENSE"><img src="https://shields.io/github/license/EM-GeekLab/nvidia-driver-installer?color=%2376b900" alt="License: Apache 2.0"></a>
  <a href="https://github.com/EM-GeekLab/nvidia-driver-installer"><img src="https://img.shields.io/github/stars/EM-GeekLab/nvidia-driver-installer?color=%2376b900" alt="Stars"></a>
<a href="https://deepwiki.com/EM-GeekLab/nvidia-driver-installer"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

<div align="center">
<table>
    <thead>
        <tr>
            <th>操作系统</th>
            <th>适配版本</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/ubuntu/ubuntu-original.svg" width="16"></sub> Ubuntu</td>
            <td><code>20.04</code>, <code>22.04</code>, <code>24.04</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/debian/debian-plain.svg" width="16"></sub> Debian</td>
            <td><code>12</code></td>
        </tr>
        <tr>
            <td>KylinOS（银河麒麟）</td>
            <td><code>V10 SP3</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/redhat/redhat-plain.svg" width="16"></sub> Red Hat Enterprise Linux</td>
            <td><code>8.x</code>, <code>9.x</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/rockylinux/rockylinux-original.svg" width="16"></sub> Rocky Linux</td>
            <td><code>8.x</code>, <code>9.x</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/oracle/oracle-original.svg" width="16"></sub> Oracle Linux</td>
            <td><code>8.x</code>, <code>9.x</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/fedora/fedora-plain.svg" width="16"></sub> Fedora</td>
            <td>官方支持 <code>41</code><br/>脚本理论支持 <code>39</code>~<code>42</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/opensuse/opensuse-original.svg" width="16"></sub> openSUSE</td>
            <td><code>15 SP6</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/opensuse/opensuse-original.svg" width="16"></sub> SUSE Linux Enterprise Server</td>
            <td><code>15 SP6</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/master/icons/amazonwebservices/amazonwebservices-original-wordmark.svg" width="16"></sub> Amazon Linux</td>
            <td><code>2023</code></td>
        </tr>
        <tr>
            <td><sub><img src="https://raw.githubusercontent.com/devicons/devicon/refs/heads/master/icons/azure/azure-original.svg" width="16"></sub> Azure Linux</td>
            <td><code>2.0</code>, <code>3.0</code></td>
        </tr>
    </tbody>
</table>
</div>

> [!WARNING]
> 对于其他基于 Debian 或 RHEL 的衍生发行版，脚本也可能兼容，但未经充分测试。

### 📖 简介

本项目旨在提供一个通用的 NVIDIA 驱动安装脚本，支持多种 Linux 发行版。它通过包管理器（如 `dnf`、`apt`、`zypper` 等）自动化安装 NVIDIA 驱动，避免了手动下载和运行 `.run` 文件的繁琐过程。

同时脚本提供了高度自动化的安装体验，支持无人值守安装、幂等性操作、状态恢复和回滚机制，确保在各种环境下都能稳定运行。

### 🚀 快速开始

> [!NOTE]
> 为安全起见，推荐您采用以下两步法进行安装。这使您有机会在执行前审查脚本内容。

```bash
curl -sSL https://raw.githubusercontent.com/EM-GeekLab/nvidia-driver-installer/main/nvidia-install.sh -o nvidia-install.sh
sudo bash nvidia-install.sh
```

该命令将通过一个可交互的安装向导，帮助您完成 NVIDIA 驱动的安装。

若您需要在 CI/CD 环境或自动化脚本中使用，可以添加 `-y` 参数实现无人值守安装：
```bash
sudo bash nvidia-install.sh -y -q --auto-reboot
```

### 🛠️ 用法与选项

脚本提供了丰富的命令行参数以满足不同场景的需求。

用法: `./nvidia-install.sh [选项]`

#### 基本选项:
    -h, --help              显示此帮助信息
    -t, --type TYPE         安装类型: full, compute-only, desktop-only (默认: full)
    -m, --modules TYPE      内核模块类型: open, proprietary (默认: open)
    -l, --local             使用本地仓库安装
    -v, --version VERSION   指定驱动版本 (例如: 575)

#### 自动化选项:
    -y, --yes               自动确认所有提示 (无交互模式)
    -q, --quiet             静默模式，减少输出
    -f, --force             强制重新安装，即使已安装驱动
    -s, --skip-checks       跳过现有安装检查
    --auto-reboot           安装完成后自动重启

#### 高级选项:
    --cleanup               清理失败的安装状态并退出
    --rollback              回滚到安装前状态
    --show-exit-codes       显示所有退出码及其含义

#### 示例

*   **交互式安装 (推荐)**
    ```bash
    sudo bash nvidia-install.sh
    ```

*   **完全自动化安装 (CI/CD 环境)**
    ```bash
    sudo bash nvidia-install.sh -y -q --auto-reboot
    ```

*   **安装纯计算驱动，并使用专有内核模块**
    ```bash
    sudo bash nvidia-install.sh -t compute-only -m proprietary -y
    ```

*   **回滚所有更改**
    ```bash
    sudo bash nvidia-install.sh --rollback
    ```

*   **查看所有退出码含义**
    ```bash
    ./nvidia-install.sh --show-exit-codes
    ```

### ✨ 项目特性

本脚本旨在解决手动或使用官方 `.run` 文件安装方式的种种不便，提供一个更现代化、更可靠的解决方案。

* **🤖 高度自动化**
    * 通过 `-y` (yes) 和 `-q` (quiet) 等参数，可实现完全无交互的静默安装，无需人工干预。
    * 自动检测操作系统发行版、版本及 GPU 架构，并选择最佳安装策略。
    * 自动处理现有驱动冲突，并根据用户选择或自动化策略进行清理。

* **🔄 幂等性与状态恢复**
    * 脚本支持**幂等操作**，可以安全地重复运行。如果驱动已正确安装，脚本会检测到并跳过，不会造成系统损坏。
    * 安装过程中的每一步都会被记录。如果脚本意外中断（如网络问题、SSH 断开），下次运行时会自动提示从断点处**恢复安装**，无需从头开始。

* **⏪ 可靠的回滚机制**
    * 在执行任何对系统有实质性修改的操作前（如安装软件包、添加仓库），脚本会记录相应的“撤销”操作。
    * 如果安装失败或您想卸载驱动，只需运行 `--rollback` 参数，即可将系统**恢复到安装前的状态**。

* **🔒 Secure Boot 智能处理**
    * 自动检测系统的 UEFI Secure Boot 状态。
    * 如果 Secure Boot 已启用，脚本会提供详细的解释和多种解决方案（禁用 SB 或配置 MOK 密钥）。
    * 在交互模式下，可以引导用户自动生成并注册 MOK 密钥，以满足 Secure Boot 的签名要求。

* **⚙️ 灵活的安装选项**
    * 支持**开源** (`open`) 和**专有** (`proprietary`) 内核模块的选择。
    * 支持**完整** (`full`)、**纯计算** (`compute-only`) 和**纯桌面** (`desktop-only`) 三种安装类型，满足不同场景的需求。
    * 支持通过 NVIDIA 官方网络仓库或本地仓库进行安装。


### 🎯 适用场景

本脚本在以下场景中表现尤为出色：

* **数据中心与服务器集群**: 需要对大量服务器进行统一、可重复的驱动部署。自动化和幂等性特性可确保部署的一致性和可靠性。
* **DevOps & CI/CD 环境**: 在自动化流水线中，需要一个可预测、有明确退出码的脚本来构建包含 NVIDIA 驱动的镜像或环境。
* **多发行版环境**: 支持同时为多台安装不同发行版的机器安装 NVIDIA 驱动，脚本会自动识别并适配。统一的部署标准可以减少维护成本。

### 🆚 与 Runfile 安装方式对比

| 特性            | 本脚本 (包管理器方式)                                                       | 官方 `.run` 文件                                                          |
| :-------------- | :-------------------------------------------------------------------------- | :------------------------------------------------------------------------ |
| **集成度**      | ✅ **高**：与系统包管理器（`dnf`/`apt`/`zypper`）深度集成，依赖关系清晰。    | ❌ **低**：独立于包管理器之外，像“空降”到系统中，可能与系统库冲突。        |
| **卸载**        | ✅ **干净、彻底**：可通过包管理器轻松卸载，`--rollback` 功能可恢复所有更改。 | ⚠️ **困难、不彻底**：`nvidia-uninstall` 可能有残留，手动清理复杂且易出错。 |
| **自动化**      | ✅ **非常容易**：丰富的命令行参数和环境变量为自动化量身定制。                | ⚠️ **较复杂**：需要拼接大量 `--silent` 系列参数，容错性差。                |
| **幂等性**      | ✅ **是**：可安全地重复运行。                                                | ❌ **否**：重复运行通常会导致安装失败或冲突。                              |
| **回滚**        | ✅ **支持**：一键回滚到安装前状态。                                          | ❌ **不支持**：无任何回滚机制。                                            |
| **Secure Boot** | ✅ **智能处理**：自动检测并提供解决方案，可辅助 MOK 签名。                   | ❌ **不支持**：需要用户在安装前手动处理所有 Secure Boot 相关问题。         |
| **离线安装**    | ⚠️ **间接支持**：需要先搭建本地仓库。                                        | ✅ **直接支持**：`.run` 文件本身就是离线安装包。                           |
| **最新驱动**    | ⚠️ **依赖仓库**：驱动版本更新速度取决于 NVIDIA 官方仓库。                    | ✅ **最快**：通常 NVIDIA 官网会最先发布 `.run` 格式的最新驱动。            |



---
<p align="center">
    如果这个项目对您有所帮助，请点击仓库右上角的 ⭐ Star 并分享给更多的朋友！
</p>
<p align="center">
    <a href="https://star-history.com/#EM-GeekLab/nvidia-driver-installer&Date">
     <picture>
       <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=EM-GeekLab/nvidia-driver-installer&type=Date&theme=dark" />
       <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=EM-GeekLab/nvidia-driver-installer&type=Date" />
       <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=EM-GeekLab/nvidia-driver-installer&type=Date" />
     </picture>
    </a>
</p>