# ServiceHub — macOS 本地服务可视化管理程序

> 基于 **Swift 6 + SwiftUI** 原生开发，专为 macOS 设计的本地服务集中管理、进程守护与日志查看工具。
> 将分散在本地各处的 Shell 脚本（如 GPT-Load、frpc 等）、Homebrew 服务（Redis、MariaDB 等）收敛到一个美观的可视化原生面板中统一拉起、守护与监控。

---

## 界面与核心特性

- **原生 macOS 体验**：
  - 双栏主窗口 + 状态徽章（运行中、已停止、启动中、异常等）；
  - **顶部菜单栏常驻 (MenuBarExtra)**：快速查看所有服务运行状态，菜单内一键启停；
- **灵活的命令登记式纳管**：
  - 任意服务只需填入启动命令、停止命令与状态检测命令即可；
  - 内置快速模板（自定义脚本、Homebrew 服务）；
  - 提供「**测试运行启动命令**」按钮，即时验证命令有效性与输出。
- **后台健康探测与自动守护 (Supervisor)**：
  - 支持 HTTP URL 接口探活（如 `/health`）与命令退出码探活双机制；
  - 针对自启守护服务，若非正常退出，后台自动尝试重启恢复；
- **实时日志查看与过滤 (LogView)**：
  - 支持增量 tail 跟踪文件日志（如 `gpt-load.log`、`frpc.log`）；
  - 实时关键字过滤与语法高亮（Error/Warn/Info 自动识别彩色呈现）；
  - 一键在访达中定位原始日志文件。
- **配置单文件 YAML 持久化与一键备份**：
  - 配置文件统一保存在 `~/Library/Application Support/ServiceHub/services.yaml`；
  - 界面提供一键「导出服务配置备份」与「从备份恢复配置」，换机或重装秒级还原。

---

## 快速运行与构建

### 方式 1：直接运行构建脚本生成 macOS 原生 `.app`（推荐）

```bash
cd /Users/jockiller/Documents/workspace/git_work/my/servicehub
./scripts/build_app.sh

# 打开应用
open build/ServiceHub.app
```
编译完成后，你也可以将 `build/ServiceHub.app` 移动至 `/Applications` 应用程序目录中，放入 Dock 栏方便随时打开。

### 方式 2：使用 SwiftPM 开发运行

```bash
cd /Users/jockiller/Documents/workspace/git_work/my/servicehub
swift run
```

---

## 已内置纳管的服务示例

初次启动时，应用会自动在 `services.yaml` 中初始化你本机已有的核心服务，开箱即用：

| 服务名称 | 服务标识 | 启动命令 | 停止命令 | 日志路径 | 探活地址 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **GPT-Load** | `gpt-load` | `.../ai/gpt_load/gpt_load start` | `.../ai/gpt_load/gpt_load stop` | `~/env/gpt_load/gpt-load.log` | `http://127.0.0.1:3001/health` |
| **FRP Client** | `frpc` | `.../other/frp/frpc start` | `.../other/frp/frpc stop` | `~/env/frp/frpc.log` | 脚本退出码检测 |
| **Redis** | `redis` | `brew services start redis` | `brew services stop redis` | — | brew 状态检测 |

---

## 目录结构说明

```text
my/servicehub/
├── DESIGN.md                        # 系统架构与程序设计文档
├── README.md                        # 本说明文档
├── Package.swift                    # Swift Package 清单
├── scripts/
│   └── build_app.sh                 # 编译并打包 Release ServiceHub.app 脚本
└── Sources/ServiceHub/
    ├── App/
    │   └── ServiceHubApp.swift      # 程序入口、窗口与菜单栏常驻组件
    ├── Models/
    │   └── Service.swift            # 核心数据模型与状态枚举
    ├── Store/
    │   └── ServiceStore.swift       # YAML 配置持久化与增删改查
    ├── Core/
    │   ├── ProcessRunner.swift      # Shell 命令执行引擎（超时与环境变量补全）
    │   ├── HealthProbe.swift        # HTTP 探活与状态命令探测
    │   ├── Supervisor.swift         # 服务守护器与后台轮询恢复机制
    │   └── LogTail.swift            # 文件日志增量监听与环形缓冲
    └── Views/
        ├── MainWindow.swift         # 主窗口分栏布局与备份导入导出
        ├── ServiceRow.swift         # 列表服务项行视图
        ├── ServiceDetailView.swift  # 服务详情面板与启停操作
        ├── ServiceEditorSheet.swift # 添加/编辑服务表单与命令测试
        └── LogView.swift            # 实时日志查看器与过滤
```
