# ServiceHub 程序设计文档

| | |
|---|---|
| 项目名称 | ServiceHub — macOS 本地服务可视化管理程序 |
| 文档版本 | v1.0 |
| 技术栈 | Swift 6 + SwiftUI（原生 macOS App） |
| 目标系统 | macOS 13+（Ventura 及以上，arm64 / x86_64） |
| 文档状态 | 设计定稿，待开发 |

---

## 1. 背景与目标

### 1.1 背景

本机存在大量分散管理的本地服务（GPT-Load、frpc、redis、mariadb 等），各自以独立 shell 脚本启停，存在以下痛点：

- 启停命令分散、无统一入口，依赖记忆与文档；
- 服务崩溃后无人守护，需人工发现并重启；
- 状态、日志查看方式各异（tail 文件 / curl 接口 / 脚本输出）；
- 配置无统一备份，换机或重装恢复成本高。

### 1.2 目标

| 编号 | 目标 | 衡量标准 |
|---|---|---|
| G1 | 统一纳管 | 任意服务通过「登记命令」方式纳入，3 分钟内完成一个服务的接入 |
| G2 | 统一守护 | 标记自启的服务随 App 启动自动拉起；异常退出 30 秒内自动恢复或标记异常 |
| G3 | 可视可查 | 图形化状态面板；日志窗口支持实时滚动与关键字过滤 |
| G4 | 可备份 | 服务登记表一键导出/导入（单文件），可跨机器恢复 |

### 1.3 非目标（明确不做）

- 不做远程主机管理（仅本机）；
- 不生成/管理 launchd plist——服务由 ServiceHub 进程自身守护（见 §4.1 决策）；
- 不做服务依赖编排（如「A 启动成功后再启动 B」）；
- 不做 macOS 系统级守护进程（LaunchDaemon / root 权限服务）。

---

## 2. 用户故事

| 编号 | 角色 | 故事 | 验收要点 |
|---|---|---|---|
| U1 | 开发者 | 我把 `run.sh start` 填进表单，服务出现在列表并可一键启停 | 表单「测试运行」显示退出码与输出 |
| U2 | 开发者 | 我重启 Mac 后，gpt-load 和 frpc 自动恢复运行 | 登录后 60s 内自动拉起 |
| U3 | 开发者 | frpc 崩溃后我不需要管，它自己恢复了 | 崩溃 → 自动重拉 → 状态灯保持绿色 |
| U4 | 开发者 | frpc 持续失败时我能立刻知道 | 状态灯变红 + 系统通知 |
| U5 | 开发者 | 排查问题时我在 App 里看日志并搜关键字 | 日志实时滚动，过滤响应 < 100ms |
| U6 | 开发者 | 我换新 Mac，导入备份文件后所有服务恢复登记 | 导入后服务列表与命令完整还原 |
| U7 | 开发者 | 我在菜单栏就能快速停掉某个服务 | 无需打开主窗口 |

---

## 3. 系统架构

### 3.1 架构总览

单进程设计：UI、守护逻辑、日志采集运行在同一 App 进程内，通过 GCD/actor 隔离并发。

```
┌────────────────────────────────────────────────────────────┐
│                 ServiceHub.app（单进程）                     │
│                                                            │
│  ┌─────────────────┐      ┌─────────────────────────────┐  │
│  │   UI 层 (SwiftUI)│      │        状态层 (@MainActor)   │  │
│  │  MainWindow      │◀────▶│  AppState / ServiceStore    │  │
│  │  MenuBarExtra    │      │  (服务注册表 + 运行态缓存)     │  │
│  │  LogSheet        │      └──────────────┬──────────────┘  │
│  │  ServiceForm     │                     │                 │
│  └─────────────────┘                     │                  │
│                                          ▼                  │
│  ┌────────────────────── 核心服务层 ─────────────────────┐   │
│  │  ProcessRunner   执行命令 / 托管子进程 / 进程组清理      │   │
│  │  HealthProbe     定时探测（actor，10s 周期）            │   │
│  │  Supervisor      守护策略 / 退避重启 / 异常判定          │   │
│  │  LogTail         文件 tail / 管道采集 / 环形缓冲 / 轮转  │   │
│  │  ConfigRepo      services.yaml 读写 / 备份导入导出      │   │
│  │  Notifier        UserNotifications 封装               │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

### 3.2 模块职责

| 模块 | 职责 | 关键约束 |
|---|---|---|
| ServiceStore | 服务登记表的增删改查、YAML 持久化、运行态缓存 | 唯一写盘入口；`@MainActor` |
| ProcessRunner | 同步/异步执行 shell 命令；托管长期子进程；进程组终止 | 所有命令经 `/bin/bash -c`；不使用 shell 注入不安全输入 |
| HealthProbe | 按优先级探测服务状态：HTTP URL → status 命令 → 进程存活 | actor 隔离，超时 3s |
| Supervisor | 守护循环：对 autoStart 服务执行启动与恢复；退避策略；异常通知 | 独立 Task；不直接碰 UI |
| LogTail | 文件型：DispatchSource 监听追加；管道型：读 pipe→缓冲→落盘 | 环形缓冲 2MB；文件轮转 5MB×3 |
| ConfigRepo | YAML 序列化；备份导出/导入；schema 版本迁移 | 导入前校验，防注入 |
| Notifier | 系统通知封装 | 仅异常/恢复事件通知，避免打扰 |

### 3.3 并发模型

- 主线程：SwiftUI 渲染 + ServiceStore（`@MainActor`）；
- HealthProbe / Supervisor：各自独立 actor / Task，通过 `AsyncStream` 把状态变化回传主线程；
- ProcessRunner 命令执行：`DispatchQueue(label:)` + `Process.terminationHandler`，避免阻塞主线程；
- 日志采集：每服务一个串行队列；UI 读取走主线程发布的快照。

---

## 4. 关键设计决策

### 4.1 D1：守护方式 = 自管进程（非 launchd）

**决策**：服务进程由 ServiceHub 以子进程方式拉起并守护，不写入 launchd。

**理由**：
1. 用户需求是「程序拉起统一守护」——状态与控制权集中在 App 内，行为可预测；
2. 兼容任意命令（脚本、brew、前台二进制），无需为每个服务生成 plist；
3. `SMAppService`（macOS 13+）已提供登录自启与系统设置可视化管理，App 自身常驻即可覆盖开机自启诉求。

**代价与缓解**：
- App 被强退则守护失效 → 退出时弹窗让用户选择「保持服务运行/停止所有/取消」（§7.4）；
- 服务不享受 launchd 的 KeepAlive 系统级保活 → 本场景为开发机工具，可接受。

### 4.2 D2：命令执行 = bash -c 单字符串

**决策**：用户登记的是**命令字符串**（如 `/path/run.sh start`、`brew services start redis`），执行时统一 `bash -c`。

**理由**：灵活性最高，管道、环境变量、多命令皆可用；符合用户「填脚本路径或命令」的诉求。

**安全约束**：命令来自用户本人配置文件，信任边界为本机用户；导入他人备份文件时 UI 明确警告并列出全部命令供确认。

### 4.3 D3：状态判定三级回退

```
1) healthCheckURL 存在  → HTTP GET，2xx/3xx = running（超时 3s）
2) statusCommand 存在   → bash -c 执行，exit 0 = running
3) 均未配置             → 判断被托管子进程 pid 存活（前台命令型）；
                          脚本型无 pid 则显示 unknown（黄灯）并提示补配置
```

### 4.4 D4：持久化 = YAML（Yams），格式即备份格式

`services.yaml` 是唯一事实来源；「备份导出」即复制该文件，「导入」即校验后覆盖。选 YAML 而非 JSON：手改友好、可注释。唯一第三方依赖 Yams（SPM）。

### 4.5 D5：日志双通道

| 服务类型 | 采集方式 | 展示来源 |
|---|---|---|
| 登记了 `logPath`（脚本型，如 gpt-load/frpc） | DispatchSource 监听文件追加，增量读取 | 实时行 + 可「打开原始文件」 |
| 未登记 logPath（前台命令型） | 拦截子进程 stdout/stderr 管道 | 内存环形缓冲（2MB）+ 落盘 `logs/<id>.log` |

---

## 5. 数据模型

### 5.1 services.yaml

```yaml
version: 1
services:
  - id: gpt-load
    name: GPT-Load
    icon: bolt                       # SF Symbol，可选
    autoStart: true
    kind: script                     # script | foreground
    startCommand: /Users/jockiller/env/gpt_load/run.sh start
    stopCommand: /Users/jockiller/env/gpt_load/run.sh stop
    statusCommand: /Users/jockiller/env/gpt_load/run.sh status
    logPath: /Users/jockiller/env/gpt_load/gpt-load.log
    healthCheckURL: http://127.0.0.1:3001/health
  - id: frpc
    name: FRP Client
    autoStart: true
    kind: script
    startCommand: /Users/jockiller/env/frp/run.sh start
    stopCommand: /Users/jockiller/env/frp/run.sh stop
    statusCommand: /Users/jockiller/env/frp/run.sh status
    logPath: /Users/jockiller/env/frp/frpc.log
  - id: redis
    name: Redis (brew)
    autoStart: false
    kind: script
    startCommand: /opt/homebrew/bin/brew services start redis
    stopCommand: /opt/homebrew/bin/brew services stop redis
    statusCommand: /opt/homebrew/bin/brew services list --json
```

字段说明：

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✓ | 唯一标识（小写字母数字连字符），用于目录名与日志文件名 |
| `name` | ✓ | 显示名 |
| `kind` | ✓ | `script`：命令即完整启停语义；`foreground`：startCommand 为前台进程，由 App 直接托管 |
| `autoStart` | ✓ | App 启动时是否自动拉起 |
| `startCommand` | ✓ | 启动命令 |
| `stopCommand` | ✗ | 未填时：foreground 型发 SIGTERM，script 型不可停止（UI 置灰） |
| `statusCommand` | ✗ | 见 D3 回退链 |
| `logPath` | ✗ | 文件日志路径 |
| `healthCheckURL` | ✗ | HTTP 探活地址 |
| `icon` | ✗ | SF Symbol 名称 |

### 5.2 Swift 类型

```swift
enum ServiceKind: String, Codable { case script, foreground }

enum ServiceStatus: String {
    case running, stopped, failed, probing, unknown
}

struct Service: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String?
    var autoStart: Bool
    var kind: ServiceKind
    var startCommand: String
    var stopCommand: String?
    var statusCommand: String?
    var logPath: String?
    var healthCheckURL: String?
}

// 运行态（不落盘，重启后重建）
struct RuntimeState {
    var status: ServiceStatus = .unknown
    var pid: pid_t?                  // foreground 型托管进程
    var startedAt: Date?
    var lastProbeAt: Date?
    var restartCount: Int = 0        // 本次会话内自动重启次数
}
```

### 5.3 磁盘布局

```
~/Library/Application Support/ServiceHub/
├── services.yaml
└── logs/
    └── <service-id>.log            # 仅 foreground 型落盘
~/Library/Preferences/com.jockiller.servicehub.plist   # UserDefaults
```

UserDefaults 键：`launchAtLogin`（Bool）、`probeInterval`（Double，默认 10）、`notifyOnFailure`（Bool，默认 true）。

---

## 6. 核心流程

### 6.1 启动流程

```
App 启动
  ├─ ConfigRepo.load() 读取 services.yaml（不存在则创建空表 + 引导页）
  ├─ 恢复登录自启注册状态（SMAppService）
  ├─ 为每个服务创建 LogTail（logPath 型）并从文件尾部预读 200 行
  └─ Supervisor.start():
       对 autoStart==true 的服务：
         probe → already running? 跳过（容忍脚本已在跑的情况）
                → not running? startService()
```

### 6.2 启动服务（start）

```
startService(s):
  1. ProcessRunner.run(s.startCommand, timeout: 30s)
  2. 若 kind == foreground:
       不适用——foreground 型不走命令行 start，
       而是直接 spawnSupervised(startCommand) 持有管道与 pid
  3. 等待 1s → probe()
  4. running  → 状态灯绿，记录 startedAt
     非 running → 重试 1 次 → 仍失败 → failed（红）+ 通知
```

### 6.3 停止服务（stop）

```
stopService(s):
  1. script 型且配置了 stopCommand → bash -c 执行，等待完成（超时 15s）
  2. foreground 型 → kill(-pgid, SIGTERM)
  3. 5s 后仍存活 → kill(-pgid, SIGKILL)
  4. probe 确认 → stopped（灰）
```

### 6.4 守护与恢复（Supervisor 循环）

```
每 probeInterval（默认 10s）：
  for s in services:
    expected = s.autoStart ? running : (上次状态为 running ? running : stopped)
    actual   = probe(s)
    if expected == .running && actual != .running:
        if s.restartCount < 3:
            延迟 backoff(restartCount) = 1s * 2^restartCount
            startService(s); restartCount += 1
        else:
            status = .failed；Notifier.send("服务 [name] 连续重启失败")
    if actual == .running && 上次为 .failed:
        restartCount = 0；Notifier.send("服务 [name] 已恢复")
```

### 6.5 日志采集（LogTail）

- **文件型**：`DispatchSource.makeFileSystemObjectSource(fd, .write)` 监听追加；从文件末尾 offset 增量读；过滤在 UI 层做（对快照正则/包含匹配）；
- **管道型**：`readabilityHandler` 读 pipe → 追加环形缓冲（2MB）→ 异步落盘 `logs/<id>.log`；落盘文件 > 5MB 轮转为 `.log.1`（最多 3 份，超出删除最旧）。

---

## 7. UI 设计

### 7.1 主窗口

```
┌────────────────────────────────────────────────────────────┐
│  ServiceHub                          搜索…      [ + 添加 ]  │
├──────────────────┬─────────────────────────────────────────┤
│ ● GPT-Load       │  GPT-Load                    ● 运行中    │
│ ● FRP Client     │  v2.0.0-rc.9 · 自启 · 已运行 3h 12m      │
│ ○ Redis (brew)   │  [ 启动 ] [ 停止 ] [ 重启 ]  [ 日志 ] [ ✎ ]│
│ ○ MariaDB        │ ──────────────────────────────────────── │
│                  │  实时日志                    [过滤: ____] │
│ ＋ 从模板添加…     │  21:24:01 [I] server started :3001      │
│                  │  21:24:01 [I] database ready            │
│                  │  ▼ (自动滚动，可暂停)                      │
└──────────────────┴─────────────────────────────────────────┘
```

状态灯：绿 `running` / 灰 `stopped` / 红 `failed` / 黄 `probing·unknown`。

### 7.2 菜单栏（MenuBarExtra）

- 图标：聚合状态（全绿 `dot`，存在异常 `exclamationmark.triangle`）；
- 下拉：每服务一行 `[状态点] 名称 —— 开关 Toggle`；分隔线；`打开主窗口`、`全部启动`、`全部停止`、`退出…`。

### 7.3 添加/编辑服务表单

- 模板三选一：`脚本服务` / `brew 服务`（选名称自动填三条命令）/ `前台命令`；
- 字段：名称、图标、自动启动 Toggle、start/stop/status 命令、日志路径、健康检查 URL；
- 「测试运行」：执行当前命令，展示退出码 + 前 10 行输出 + 耗时；
- 校验：id 自动从名称 slug 生成（可改、唯一）；start 必填。

### 7.4 退出确认

App 退出（⌘Q / 菜单退出）时弹窗：

> 仍有 N 个服务由 ServiceHub 守护。
> [保持服务运行] [停止所有服务并退出] [取消]

---

## 8. 接口与权限

| 项 | 说明 |
|---|---|
| 沙盒 | **不开** App Sandbox（需自由 spawn 任意用户命令与读写 `~/Library` 外路径，如 `/Users/jockiller/env/...`） |
| 登录自启 | `SMAppService.mainApp.register()`；系统设置 > 通用 > 登录项中可见、可管理 |
| 通知 | `UNUserNotificationCenter`，申请 alert 权限 |
| 网络 | 仅出站（健康检查 HTTP GET、brew 命令）；无监听端口 |
| 敏感信息 | services.yaml 可能含带 token 的命令 → 文件权限 `0600`；导出备份时提示「文件包含命令行，可能含密钥」 |

---

## 9. 错误处理

| 场景 | 行为 |
|---|---|
| services.yaml 损坏 | 启动时解析失败 → 保留损坏文件为 `services.yaml.bad-<timestamp>`，以空表启动并通知 |
| start 命令非零退出 | UI 显示命令输出尾部 20 行；状态 failed |
| stop 超时 | SIGKILL 进程组后标记 stopped，日志记录强杀事件 |
| logPath 文件不存在 | 日志面板显示「等待文件创建」，每 5s 重试监听 |
| 健康检查 URL 不可达 | 按 D3 回退到下一级判定；URL 异常不阻塞其他探测 |
| 导入备份版本更高 | 拒绝导入并提示版本不支持 |

---

## 10. 测试策略

| 层级 | 范围 | 工具 |
|---|---|---|
| 单元 | ConfigRepo 序列化/迁移、Service id 校验、退避计算、环形缓冲 | XCTest |
| 单元 | ProcessRunner：`echo`、`exit 3`、长输出、超时命令 | XCTest（真实 Process） |
| 集成 | 用 `/tmp` 下的 dummy 脚本（start 写 pid 文件 / stop kill）验证守护恢复 | XCTest + 临时目录 |
| UI | XCUITest：添加服务→启停→状态灯断言 | XCUITest |
| 手工 | 真实服务接入（gpt-load / frpc / redis）跑 24h 观察守护与日志 | 手动 |

---

## 11. 里程碑

| 阶段 | 范围 | 出口标准 |
|---|---|---|
| P1 骨架 | 工程 + 主窗口 + YAML 存取 + 手动启停/状态 | 纳管 gpt-load、frpc、redis 三真实服务，可替代手敲脚本 |
| P2 守护 | autoStart、10s 探测、退避重启、异常通知 | 杀掉 frpc 进程 30s 内自动恢复 |
| P3 日志 | LogTail 双通道 + 过滤 + 轮转 | gpt-load 日志实时滚动、过滤即时 |
| P4 完整形态 | MenuBarExtra + brew 模板 + healthCheckURL + 表单测试运行 | 菜单栏可完成日常启停 |
| P5 发布 | 备份导入导出 + 退出策略 + SMAppService + 图标 | 打包 .app 可分发 |

每个阶段以 `xcodebuild -scheme ServiceHub build` 与对应测试通过为完成标准。

---

## 12. 风险与开放问题

| 风险/问题 | 影响 | 对策 |
|---|---|---|
| App 强退导致守护失效 | 中 | 退出确认弹窗；文档说明「完全关机型守护需 launchd」 |
| brew services 输出格式随版本变化 | 低 | status 优先 `--json`，失败回退文本解析 |
| 用户在 services.yaml 手写非法命令 | 低 | 测试运行暴露错误；执行失败显示原始 stderr |
| macOS TCC：前台 App 读受保护目录 | 中 | 本设计所有路径已在用户目录下；如未来纳入 Documents 下配置，提示用户授予「文件与文件夹」权限 |
| Yams 依赖供应链 | 低 | 锁定版本；必要时换 JSON（结构不变仅换后缀） |

---

## 附录 A：环境确认（2026-09-07）

- Xcode 26.6 (17F113)、Swift 6.3.3、macOS 27.0 (arm64)；
- `launchctl`、`brew` 可用；现有待纳管服务：gpt-load（run.sh + 3001/health）、frpc（run.sh + frpc.log）、redis、mariadb（brew services）。