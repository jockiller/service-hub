# ServiceHub

<p align="center">
  <img src="Resources/AppIcon.svg" width="128" height="128" alt="ServiceHub Logo" />
</p>

<p align="center">
  <b>A modern, native macOS local service manager and supervisor.</b><br>
  Unified management for Shell scripts, Homebrew, macOS Apps, and Docker containers.
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

## 💡 Overview

In daily software development and local DevOps, developers often manage numerous heterogeneous background services: custom startup/shutdown Shell scripts (e.g. reverse proxy tunnels, gateway loaders), Homebrew background services (Redis, MariaDB), native macOS desktop tools (DBX, local agents), and Docker containers.

**ServiceHub** is built natively using **Swift 6 and SwiftUI**. It converges all these disparate services into a clean, modern, and unified macOS dashboard with **automated health supervision, crash-loop backoff circuit breaker, Shortcuts-style system preconditions, and real-time log streaming**.

---

## 📸 Screenshots

### 1. Modern Dashboard & Bottom Real-Time Log Console
> Seamlessly toggle between **High-Contrast Card Grid** and **List View**. Inspect real-time native application icons, status badges, accurate process PIDs, and running uptime. Click any card to track its live log stream with keyword highlighting.

![Dashboard Card View and Log Console](assets/screenshots/main-window.png)

---

### 2. Four Built-in Service Templates
> Wizard supporting **Custom Scripts/Commands**, **Homebrew Auto-Scanning**, **Native macOS Apps (.app)**, and **Docker Containers Auto-Scanning** with automated command generation.

![Add Service Wizard](assets/screenshots/add-service.png)

---

### 3. Shortcuts-Style Preconditions & Crash-Loop Protection
> Configure startup preconditions (Internet online, connected to specific Wi-Fi SSID, plugged into AC power, external display connected, etc.). The supervisor elegantly awaits conditions before launching. Built-in sliding-window crash-loop backoff prevents runaway restart loops.

![Service Configuration and Preconditions](assets/screenshots/edit-service.png)

---

### 4. Native Menu Bar Popover Center (MenuBarExtra)
> Compliant monochrome template menu bar icon. Click to open a dedicated Popover panel where every single service offers independent **Start**, **Stop**, and **Restart** controls, along with live status and uptime indicators.

![Menu Bar Extra Popover](assets/screenshots/menubar-panel.png)

---

## ✨ Key Features

- **Unified Management Across 4 Service Types**:
  - **Custom Scripts / Commands**: Manage shell scripts with start, stop, and status commands, equipped with Finder file picker buttons;
  - **Homebrew Services**: Automatically scans installed `brew services` (Redis, MariaDB, Nginx, etc.) and auto-completes lifecycle commands;
  - **macOS Applications (.app)**: Select applications directly from `/Applications`. Automatically extracts high-resolution Squircle icons, Bundle IDs, and checks status using native `NSRunningApplication` to avoid false positives;
  - **Docker Containers**: Scans local Docker containers with one-click adoption for `docker start/stop/inspect` commands.
- **macOS Shortcuts-Style Preconditions**:
  - **Network**: Internet Connected, Network Disconnected (Offline mode), Wi-Fi Connected (optional SSID filtering), Wi-Fi Disconnected, VPN/Proxy interface active;
  - **Bluetooth**: Bluetooth On/Off, Specific Bluetooth Device Connected (e.g. AirPods Pro);
  - **Power & Hardware**: AC Power connected, On Battery power, External Display connected, Volume/Disk mounted;
  - **Advanced**: Local Port available, Host reachable (Ping/HTTP), Custom Shell command check.
- **Crash-Loop Backoff & Circuit Breaker**:
  - Automatically recovers and restarts failed auto-start services;
  - Configurable sliding time window and maximum consecutive failure count (e.g., stops auto-restart if failing 3 times within 60s) to protect CPU and system stability.
- **Status Command Specification (Important)**:
  - ServiceHub determines whether a service is alive by executing the "Status Command" and reading its **process exit code** — the command's stdout content is **never used for liveness detection**;
  - **Exit code `0` = Running, non-zero = Stopped**. This is the only liveness criterion;
  - ⚠️ **Warning**: Many shell scripts (especially those with `set -e` or internal `grep` calls) may return a non-zero exit code even when the service is healthy, or always `exit 0` regardless of the service state. Both situations distort ServiceHub's status detection (e.g., a crashed service may keep showing "Running", and the crash guardian will never trigger an auto-restart);
  - ✅ **Recommended patterns**:
    ```bash
    # 1. Detect a process with pgrep (recommended)
    pgrep -f "frpc" >/dev/null

    # 2. Check whether a Homebrew service is started
    brew services list | grep "^redis" | grep -q "started"

    # 3. Check whether a Docker container is Running
    docker inspect -f '{{.State.Running}}' my-container | grep -q "true"

    # 4. Check whether a port is being listened on
    lsof -i :8080 >/dev/null 2>&1
    ```
  - ❌ **Bad examples**: `echo "Service is running"` (always exits 0, misjudged as alive regardless of state), `tail -n 5 app.log` (exit code depends on the last log line's content, unrelated to the process state);
  - 💡 **Debugging tip**: Run your status command manually in Terminal, then run `echo $?` to verify the exit code is `0` (running) / non-zero (stopped). Make sure the script always returns a **reliable, distinguishable exit code**;
  - 📋 **Template for self-managed scripts**: If you write your own service management script (e.g. `xxx.sh start|stop|status`), make sure the `status` branch **explicitly sets exit codes**, for example:
    ```bash
    do_status() {
        if is_running; then
            log "Service: running (PID $(cat "${PID_FILE}"))"
            exit 0          # ✅ Running must explicitly exit 0
        else
            log "Service: not running."
            exit 1          # ✅ Stopped must explicitly exit non-zero
        fi
    }
    ```
    ⚠️ Watch out for two common pitfalls:
    1. **Never rely on implicit return values at the end of a branch** — if the last line of `do_status` is `log "xxx"`, `networksetup ...`, or another external command, the function's exit code follows that command instead of the real service state. Always `exit 0` / `exit 1` explicitly in every branch;
    2. **Beware of `set -e` interference** — with `set -Eeuo pipefail`, any intermediate command failure inside the script (e.g. `grep` missing a match, a missing file) aborts the whole script with a non-zero code, which may conflict with your status semantics. Add `|| true` after intermediate commands in the status path, or keep status-detection logic isolated from the global `set -e` scope.
- **Real-Time Log Streamer**:
  - Lightweight file tail powered by AppKit `DispatchSource`;
  - **Bounded line buffer**: the console keeps only the latest **300 lines** of live logs — memory stays constantly tiny no matter how large the log file grows, and the UI stays perfectly smooth;
  - When the display cap is exceeded, a truncation notice appears at the top with a one-click "Open Full File" shortcut to view complete history in Finder;
  - Live keyword filtering, ANSI-colored highlighting, and a **one-click Clear console** button (the on-disk log file is never touched);
  - Automatic scroll-to-bottom and one-click reveal log file in Finder.
- **Cloud Backup & Multi-Mac Sync (OneDrive / iCloud)**:
  - Human-readable YAML configuration format;
  - Customize config storage path in Settings (e.g. point to OneDrive or iCloud Drive) with automatic data migration.
- **Customizable Appearance & Launch-at-Login**:
  - Option to hide Dock icon (pure menu bar tray mode);
  - Option to toggle menu bar icon with safety interlock protection;
  - Native launch-at-login integration via macOS 13+ `SMAppService`.

---

## 🚀 Quick Start

### Option 1: Download Pre-built Release (Recommended)

Download the latest `.dmg` installer from [GitHub Releases](https://github.com/jockiller/service-hub/releases):
1. Open the `.dmg` image;
2. Drag **ServiceHub** into the **Applications** folder;
3. **First-launch Notice**: As an open-source app without an expensive Apple commercial certificate, if macOS Gatekeeper blocks opening with "unidentified developer" or "damaged", simply run this command once in Terminal:
   ```bash
   xattr -cr /Applications/ServiceHub.app
   ```
   Or right-click the app in Finder and choose **Open**.

---

### Option 2: Local Build, Codesign & DMG Creation

```bash
# 1. Clone repository
git clone git@github.com:jockiller/service-hub.git
cd service-hub

# 2. Build, perform ad-hoc codesign, and generate compressed DMG
./scripts/create_dmg.sh 1.0.0

# 3. Output files generated under build/
open build/ServiceHub-1.0.0-macOS.dmg
```

---

### Option 3: Run directly with SwiftPM

```bash
swift run
```

---

## 🛠 Tech Stack

- **Language**: Swift 6
- **UI Framework**: SwiftUI (macOS 13.0+)
- **System APIs**: AppKit, Combine, ServiceManagement, UniformTypeIdentifiers
- **Configuration**: [Yams](https://github.com/jpsim/Yams) (YAML Serialization)
- **Build Pipeline**: Swift Package Manager + `iconutil`

---

## 📄 License

Distributed under the [MIT License](LICENSE).
