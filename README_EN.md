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
- **Update & Check-Update Command Specification**:
  - **ServiceHub Lifecycle Orchestration**: When triggering "Update & Restart", ServiceHub enforces a safe pipeline: **Gracefully stops old service (releasing ports and files, pausing crash-guard) ➔ Executes update command ➔ Automatically starts/restarts service upon success**. The update script only needs to focus on downloading/replacing the binary without killing or restarting processes manually;
  - **Check-Update Command Specification**:
    - **Update Available**: The command exit code must be `0`, and standard output (stdout) must print **non-empty text describing the new version** (e.g. `v2.0.1 (current: v2.0.0)`). The first line of this output is displayed directly on the service card badge and update prompt;
    - **Already Up to Date**: The command exit code must be `0`, and standard output must be **empty** (or only printed under `--verbose`). ServiceHub detects empty output as up to date and provides feedback when checked manually;
    - **Check Failure / Error**: Exits with a non-zero code.
  - **Update Command Specification**:
    - Responsible for downloading the new program, replacing binaries, pulling git commits, or pulling container images;
    - **Reliable Exit Codes**: Must return `0` on successful upgrade; must return non-zero on failure (e.g. network timeout, build failure, checksum mismatch). When a failure is detected, ServiceHub **aborts automatic restart** and flags the service with an error to prevent crash loops.
  - ✅ **Recommended Pattern Examples**:
    - **Homebrew Service**:
      - Check command: `/opt/homebrew/bin/brew outdated --verbose <formula> 2>/dev/null || true`
      - Update command: `/opt/homebrew/bin/brew upgrade <formula>`
    - **Git-based Repository (e.g. WebUI / Script)**:
      - Check command: `git fetch origin && git log -1 --oneline HEAD..@{u}` (prints commit if remote has updates, empty if up to date)
      - Update command: `git pull`
    - **Docker Compose Service**:
      - Check command: Run a lightweight metadata-check script (recommended, see sample below), or leave empty to update manually;
      - Update command: `docker compose pull && docker compose up -d` (⚠️ `up -d` is required; a plain `docker pull` cannot recreate containers with new image layers).
  - 🐳 **Docker Zero-Bandwidth Metadata Check Specification (Recommended)**:
    > ⚠️ **Common Pitfall**: Never run `docker pull` in the "Check command", as it downloads multi-gigabyte layers on every check; also do not use the non-existent `--dry-run`.
    >
    > ✅ **Best Practice**: Use Docker's built-in `docker buildx imagetools inspect` to fetch remote Registry manifests (consuming only a few KBs of metadata) and compare against the running container's image ID:
    ```bash
    # check_docker_update.sh: Check for new remote image via lightweight metadata
    CONTAINER="vaultwarden"
    IMAGE="vaultwarden/server:latest"

    CURRENT_ID=$(docker inspect --format '{{.Image}}' "$CONTAINER" 2>/dev/null)
    ARCH=$(uname -m | sed 's/x86_64/amd64/' | sed 's/arm64/arm64/')
    REMOTE_DIGEST=$(docker buildx imagetools inspect "$IMAGE" --raw 2>/dev/null | jq -r --arg a "$ARCH" '.manifests[] | select(.platform.architecture == $a and .platform.os == "linux") | .digest' | head -n 1)

    if [ -n "$REMOTE_DIGEST" ]; then
        REMOTE_ID=$(docker buildx imagetools inspect "${IMAGE%:*}:latest@$REMOTE_DIGEST" --raw 2>/dev/null | jq -r '.config.digest')
        if [ -n "$REMOTE_ID" ] && [ "$CURRENT_ID" != "$REMOTE_ID" ]; then
            echo "New image available: ${REMOTE_ID:0:19}..."
        fi
    fi
    exit 0
    ```
  - ⚡️ **Concise Check-Update Script Example (`check_update.sh`)**:
    > Core rule: **Print version info when updates exist (exit code 0), keep stdout completely empty when up to date (exit code 0)**.
    ```bash
    #!/usr/bin/env bash
    CURRENT="v1.0.0"
    # Fetch latest GitHub Release Tag (tokenless, no rate limit)
    LATEST=$(curl -sI "https://github.com/owner/repo/releases/latest" 2>/dev/null | grep -i "^location:" | sed -e 's/.*tag\///' -e 's/[[:space:]]//g')

    # Compare versions: print ONLY when a newer version is found
    if [ -n "$LATEST" ] && [ "$LATEST" != "$CURRENT" ]; then
        echo "$LATEST (current: $CURRENT)"
    fi
    exit 0
    ```
  - ⚡️ **Direct Input Field One-liner Example**:
    ```bash
    # Suitable for pasting directly into the "Check command" input box:
    latest=$(curl -sI https://github.com/owner/repo/releases/latest 2>/dev/null | grep -i "^location:" | sed -e 's/.*tag\///' -e 's/[[:space:]]//g') && [ -n "$latest" ] && [ "$latest" != "v1.0.0" ] && echo "$latest (current: v1.0.0)" || true
    ```
  - 📋 **Full Service Lifecycle Script Template (`start|stop|check-update|update`)**:
    ```bash
    # 1. Check-update branch (check-update)
    do_check_update() {
        local current="$(get_local_version)"
        local latest="$(get_remote_version)"
        if [ "$current" != "$latest" ]; then
            echo "$latest (current: $current)"   # ✅ Update found: print info and exit 0
            exit 0
        else
            exit 0                             # ✅ Up to date: stdout empty and exit 0
        fi
    }

    # 2. Perform-update branch (update)
    do_update() {
        if download_and_replace_bin; then
            exit 0                             # ✅ Success: exit 0, ServiceHub will restart service
        else
            exit 1                             # ✅ Failure: exit non-zero, ServiceHub blocks restart
        fi
    }
    ```
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
