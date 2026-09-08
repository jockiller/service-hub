# ServiceHub

<p align="center">
  <img src="Resources/AppIcon.svg" width="128" height="128" alt="ServiceHub Logo" />
</p>

<p align="center">
  <b>一款专为 macOS 设计的现代化本地服务可视化管理工具与守护引擎</b><br>
  A modern, native macOS local service manager and supervisor.
</p>

<p align="center">
  <a href="README.md">简体中文</a> •
  <a href="README_EN.md">English</a> •
  <a href="LICENSE">MIT License</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Language-Swift%206-orange?logo=swift" alt="Language" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-red" alt="UI" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---

## 💡 项目简介

在本地开发与日常运维中，我们往往运行着大量分散的服务：本地 Shell 启停脚本（如 GPT-Load、FRP 内网穿透）、Homebrew 后台服务（Redis、MariaDB）、macOS 桌面应用程序（DBX、各类工具），以及各类 Docker 容器。

**ServiceHub** 采用 **Swift 6 + SwiftUI** 原生开发，旨在将这些异构服务全部收敛到一个优雅、极简、现代化的控制面板中，提供**统一纳管、智能守护保活、防雪崩熔断、快捷指令级前置条件判断与实时日志流监控**。

---

## 📸 界面预览

### 1. 现代化控制看板与底部实时日志流
> 支持**高对比度卡片视图 (Card Grid)** 与 **列表视图 (List)** 一键自由切换；实时展示每个服务的原生图标、运行状态徽章、真实进程 PID 与运行时长；点击任意卡片即可在底部控制台实时追踪日志流并支持关键字高亮过滤。

![主窗口卡片视图与底部日志流](assets/screenshots/main-window.png)

---

### 2. 四大类型服务一键纳管向导
> 内置 **自定义脚本**、**Homebrew 服务自动扫描**、**选取 macOS 应用程序 (.app)**、**Docker 容器自动扫描** 4 大快速模板，支持一键选取与自动填充完整控制命令。

![添加新服务向导](assets/screenshots/add-service.png)

---

### 3. 类似快捷指令（Shortcuts）的前置条件与防雪崩熔断
> 支持设置启动前置条件（如外网已连通、连接指定 Wi-Fi、插电中、外接屏等），守护引擎在前置条件未满足时优雅等待，条件达成瞬间自动拉起服务；支持设定短时间连续重启上限，触发熔断保护防止拖垮系统。

![服务编辑与前置条件配置](assets/screenshots/edit-service.png)

---

### 4. 顶部状态栏常驻控制中心 (MenuBarExtra)
> 匹配 macOS 原生规范的黑白单色 Template 状态栏图标；点击弹出专属控制卡片，每条服务均提供独立的「启动」、「关闭」、「重启」按钮，支持查看已运行时长与实时状态。

![顶部菜单栏常驻控制面板](assets/screenshots/menubar-panel.png)

---

## ✨ 核心特性

- **四大异构服务统一纳管**：
  - **自定义脚本 / 命令**：填入启动、停止、状态命令即可纳管任意复杂脚本，输入框自带「浏览文件」按钮；
  - **Homebrew 服务**：全自动异步扫描本机已安装的 `brew services`（Redis、MariaDB、Nginx 等），一键下拉挑选即可自动补齐命令；
  - **macOS 原生应用程序 (.app)**：支持直接从访达选取系统应用，自动提取应用原生高清图标（Squircle）、Bundle ID 与控制命令，通过 `NSRunningApplication` 核心接口实现 100% 精确的进程存活性检测；
  - **Docker 容器**：自动扫描本地所有 Docker 容器，一键选取纳管容器的启动、停止与状态监控。
- **类似快捷指令 (Shortcuts) 级前置条件检测**：
  - **网络环境**：外网已连通、网络已断开 (离线)、已连接 Wi-Fi (可指定 SSID 匹配)、Wi-Fi 已断开、VPN/代理已就绪；
  - **蓝牙设备**：蓝牙开启/关闭、指定蓝牙设备已连接 (如 AirPods Pro)；
  - **硬件与电源**：已连接电源适配器 (插电)、使用电池供电中、已连接外接显示器、指定外部磁盘卷宗已挂载；
  - **高级检测**：指定本地端口可用 (未占用)、目标主机可达 (Ping)、自定义 Shell 判定。
- **后台智能保活与防雪崩熔断 (Crash-Loop Backoff)**：
  - 对开启自启守护的服务，异常退出后后台自动重拉；
  - 支持自定义**时间窗口**与**最大连续重启次数**（如 60 秒内连续重试超 3 次自动熔断），防止配置错误导致死循环重启占满 CPU。
- **实时日志流监控 (Log Console)**：
  - 自动增量监听并展示服务日志（`DispatchSource` 驱动，轻量零开销）；
  - 实时关键字过滤搜索与 ANSI 彩色高亮；
  - 支持自动滚屏跟踪与一键在访达中定位原始日志文件。
- **多设备云备份支持 (OneDrive / iCloud)**：
  - 配置文件采用易读的 YAML 格式存储；
  - 设置面板支持**一键修改存储路径**（可指向 OneDrive、iCloud Drive、坚果云等），自动完成现有配置迁移，实现多台 Mac 配置自动同步。
- **外观与自启动自由定制**：
  - 支持**隐藏 Dock 栏图标**（纯托盘模式，不占 Dock 空间）；
  - 支持控制菜单栏图标显隐（内置防失踪安全互锁）；
  - 采用 macOS 13+ 原生 `SMAppService` 官方接口实现开机自启动。

---

## 🚀 快速开始

### 方式 1：直接下载安装包（推荐）

从 [GitHub Releases](https://github.com/jockiller/service-hub/releases) 页面下载最新版的 `.dmg` 安装镜像：
1. 双击打开 `.dmg` 文件；
2. 将 **ServiceHub** 拖拽至 **Applications**（应用程序）目录；
3. **首次打开说明**：因开源软件未购买苹果昂贵的商业开发者证书，若系统提示“无法验证开发者”或“已损坏”，只需打开系统「终端」运行一次以下信任命令即可：
   ```bash
   xattr -cr /Applications/ServiceHub.app
   ```
   或者：按住 `Control` 键右键点击应用图标 -> 选择“打开”。

---

### 方式 2：本地一键编译打包 Release .dmg

本项目使用标准 Swift Package Manager 驱动，无需配置复杂的 Xcode 工程：

```bash
# 1. 克隆代码仓库
git clone git@github.com:jockiller/service-hub.git
cd service-hub

# 2. 一键编译、代码签名并生成 DMG 安装镜像
./scripts/create_dmg.sh 1.0.0

# 3. 产物生成于 build/ 目录下
open build/ServiceHub-1.0.0-macOS.dmg
```

---

### 方式 3：使用 SwiftPM 直接开发调试

```bash
swift run
```

---

## 🛠 技术栈

- **开发语言**：Swift 6
- **UI 框架**：SwiftUI (macOS 13.0+)
- **系统接口**：AppKit, Combine, ServiceManagement, UniformTypeIdentifiers
- **配置文件持久化**：[Yams](https://github.com/jpsim/Yams) (YAML 解析与编码)
- **打包工具**：Swift Package Manager + 原生 `iconutil` 构建管线

---

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 许可证发布，允许免费商用、修改与分发。
