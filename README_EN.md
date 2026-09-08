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
- **Real-Time Log Streamer**:
  - Lightweight file tail powered by AppKit `DispatchSource`;
  - Live keyword filtering, search, and automatic scroll-to-bottom;
  - One-click reveal log file in Finder.
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
