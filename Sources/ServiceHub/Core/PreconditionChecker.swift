import Foundation
import AppKit
import CoreWLAN

public final class PreconditionChecker {
    @MainActor private static var cachedWifiDev: String? = nil

    @MainActor
    private static func getWifiDevice(preferred: String? = nil) async -> String {
        if let preferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines), !preferred.isEmpty {
            return preferred
        }
        if let dev = cachedWifiDev { return dev }
        let findDevCmd = "networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}'"
        let devRes = await ProcessRunner.run(command: findDevCmd, timeout: 2)
        let dev = devRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dev.isEmpty {
            cachedWifiDev = dev
            return dev
        }
        return "en0"
    }

    private static func parseIpconfigSSID(from summary: String) -> String? {
        for rawLine in summary.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("SSID") else { continue }
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "SSID" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && value != "<redacted>" {
                return value
            }
        }
        return nil
    }

    private static func parseAirPortSSID(from output: String) -> String? {
        var expectingSSID = false
        for rawLine in output.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if expectingSSID {
                expectingSSID = false
                if trimmed.hasSuffix(":"),
                   trimmed != "Current Network Information:",
                   trimmed != "Other Local Wi-Fi Networks:" {
                    let ssid = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ssid.isEmpty && ssid != "<redacted>" {
                        return ssid
                    }
                }
                continue
            }
            if trimmed == "Current Network Information:" {
                expectingSSID = true
            }
        }
        return nil
    }

    /// 检测当前 Wi-Fi 连接状态；仅在需要匹配特定 SSID 时才回退到耗时的 system_profiler
    @MainActor
    private static func checkWifiStatus(resolveSSID: Bool) async -> (isConnected: Bool, ssid: String?) {
        let cwIface = CWWiFiClient.shared().interface()
        if let cwIface, (!cwIface.powerOn() || cwIface.wlanChannel() == nil) {
            return (false, nil)
        }

        let targetDev = await getWifiDevice(preferred: cwIface?.interfaceName)
        let summaryRes = await ProcessRunner.run(command: "ipconfig getsummary \(targetDev) 2>/dev/null", timeout: 2)
        let summary = summaryRes.output

        let isConnected: Bool
        if cwIface != nil {
            // CoreWLAN 已确认上电且关联信道；若 ipconfig 明确标为未激活则视为尚未就绪
            isConnected = !(summary.contains("Active : FALSE") && !summary.contains("LinkStatusActive : TRUE"))
        } else {
            let isWifiPort = summary.contains("InterfaceType : WiFi")
            isConnected = isWifiPort && (summary.contains("LinkStatusActive : TRUE") || summary.contains("IsPublished : TRUE"))
        }

        guard isConnected else {
            return (false, nil)
        }

        var ssid: String? = cwIface?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if ssid?.isEmpty == true || ssid == "<redacted>" { ssid = nil }

        if ssid == nil {
            ssid = parseIpconfigSSID(from: summary)
        }

        if ssid == nil && resolveSSID {
            let wifiRes = await ProcessRunner.run(command: "networksetup -getairportnetwork \(targetDev) 2>/dev/null", timeout: 2)
            if wifiRes.output.contains("Current Wi-Fi Network:") {
                let candidate = wifiRes.output.components(separatedBy: "Current Wi-Fi Network:").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let candidate, !candidate.isEmpty {
                    ssid = candidate
                }
            }
        }

        if ssid == nil && resolveSSID {
            let profilerRes = await ProcessRunner.run(command: "system_profiler SPAirPortDataType 2>/dev/null", timeout: 5)
            ssid = parseAirPortSSID(from: profilerRes.output)
        }

        return (true, ssid)
    }

    /// 检查服务的前置条件是否满足
    @MainActor
    public static func check(service: Service) async -> (isSatisfied: Bool, reason: String) {
        let param = service.preconditionParam?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch service.precondition {
        case .none:
            return (true, L("就绪", "Ready"))

        // ------------------ 网络类 ------------------
        case .networkConnected:
            let cmd = "curl -sI -m 2 https://captive.apple.com/hotspot-detect.html >/dev/null 2>&1 || ping -c 1 -t 2 223.5.5.5 >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            let isOk = res.isSuccess
            AppLogger.log("[Precondition] 检查服务「\(service.name)」网络连通性: \(isOk ? "已连通" : "未连通 (curl/ping 均未响应)")")
            return isOk ? (true, L("互联网已连通", "Internet connected")) : (false, L("等待外网连接", "Waiting for internet"))

        case .networkDisconnected:
            let cmd = "curl -sI -m 2 https://captive.apple.com/hotspot-detect.html >/dev/null 2>&1 || ping -c 1 -t 2 223.5.5.5 >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return !res.isSuccess ? (true, L("当前处于离线模式", "Currently offline")) : (false, L("等待网络断开", "Waiting for network to disconnect"))

        case .wifiConnected:
            let wifiStatus = await checkWifiStatus(resolveSSID: !param.isEmpty)
            guard wifiStatus.isConnected else {
                return (false, L("等待连接 Wi-Fi", "Waiting for Wi-Fi"))
            }

            if !param.isEmpty {
                guard let currentSSID = wifiStatus.ssid, !currentSSID.isEmpty else {
                    return (false, L("已连接 Wi-Fi，但系统限制读取网络名称，等待匹配: \(param)", "Wi-Fi connected, but SSID is redacted by macOS; waiting for \(param)"))
                }
                if currentSSID.localizedCaseInsensitiveContains(param) {
                    return (true, L("已连接指定 Wi-Fi: \(currentSSID)", "Connected to specified Wi-Fi: \(currentSSID)"))
                } else {
                    return (false, L("当前为 \(currentSSID)，等待连接指定 Wi-Fi: \(param)", "Currently on \(currentSSID); waiting for \(param)"))
                }
            } else {
                if let currentSSID = wifiStatus.ssid, !currentSSID.isEmpty {
                    return (true, L("已连接 Wi-Fi: \(currentSSID)", "Wi-Fi connected: \(currentSSID)"))
                } else {
                    return (true, L("Wi-Fi 已连接", "Wi-Fi connected"))
                }
            }

        case .wifiDisconnected:
            let wifiStatus = await checkWifiStatus(resolveSSID: false)
            if !wifiStatus.isConnected {
                return (true, L("Wi-Fi 未连接", "Wi-Fi disconnected"))
            } else {
                return (false, L("等待断开 Wi-Fi", "Waiting for Wi-Fi to disconnect"))
            }

        case .vpnActive:
            let cmd = "ifconfig 2>/dev/null | grep -q 'utun'"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            return res.isSuccess ? (true, L("VPN / 代理虚拟网卡已就绪", "VPN / proxy interface ready")) : (false, L("等待 VPN / 代理连接", "Waiting for VPN / proxy"))

        // ------------------ 蓝牙类 ------------------
        case .bluetoothOn:
            let cmd = "system_profiler SPBluetoothDataType 2>/dev/null | grep -iE '(State: On|Bluetooth Power: On|Power State: 1)'"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return res.isSuccess ? (true, L("蓝牙已开启", "Bluetooth on")) : (false, L("等待蓝牙开启", "Waiting for Bluetooth to turn on"))

        case .bluetoothOff:
            let cmd = "system_profiler SPBluetoothDataType 2>/dev/null | grep -iE '(State: Off|Bluetooth Power: Off|Power State: 0)'"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return res.isSuccess ? (true, L("蓝牙已关闭", "Bluetooth off")) : (false, L("等待蓝牙关闭", "Waiting for Bluetooth to turn off"))

        case .bluetoothConnected:
            let cmd = "system_profiler SPBluetoothDataType 2>/dev/null"
            let res = await ProcessRunner.run(command: cmd, timeout: 4)
            if !param.isEmpty {
                // 检测指定设备
                if res.output.localizedCaseInsensitiveContains(param) && res.output.contains("Connected: Yes") {
                    return (true, L("已连接蓝牙设备: \(param)", "Bluetooth device connected: \(param)"))
                } else {
                    return (false, L("等待连接蓝牙设备: \(param)", "Waiting for Bluetooth device: \(param)"))
                }
            } else {
                // 任意蓝牙设备
                if res.output.contains("Connected: Yes") {
                    return (true, L("蓝牙设备已连接", "Bluetooth device connected"))
                } else {
                    return (false, L("等待蓝牙设备连接", "Waiting for Bluetooth device"))
                }
            }

        // ------------------ 电源与硬件 ------------------
        case .acPower:
            let cmd = "pmset -g batt 2>/dev/null | grep -q 'AC Power'"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            return res.isSuccess ? (true, L("已连接电源适配器", "AC power connected")) : (false, L("等待连接电源适配器 (插电)", "Waiting for AC power"))

        case .onBattery:
            let cmd = "pmset -g batt 2>/dev/null | grep -q 'Battery Power'"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            return res.isSuccess ? (true, L("正在使用电池供电", "On battery power")) : (false, L("等待断开电源切换至电池", "Waiting to switch to battery"))

        case .externalDisplay:
            let screenCount = NSScreen.screens.count
            if screenCount > 1 {
                return (true, L("已连接外接显示器 (共 \(screenCount) 块屏幕)", "External display connected (\(screenCount) screen(s)))"))
            } else {
                return (false, L("等待连接外接显示器", "Waiting for external display"))
            }

        case .volumeMounted:
            guard !param.isEmpty else {
                return (false, L("未指定磁盘名称", "Volume name not specified"))
            }
            let targetPath = param.hasPrefix("/Volumes/") ? param : "/Volumes/\(param)"
            if FileManager.default.fileExists(atPath: targetPath) {
                return (true, L("磁盘卷宗已挂载: \(targetPath)", "Volume mounted: \(targetPath)"))
            } else {
                return (false, L("等待磁盘挂载: \(targetPath)", "Waiting for volume: \(targetPath)"))
            }

        // ------------------ 高级类 ------------------
        case .portAvailable:
            guard let port = Int(param), port > 0, port <= 65535 else {
                return (false, L("请指定有效端口号 (1~65535)", "Specify a valid port (1-65535)"))
            }
            let cmd = "lsof -i :\(port) >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            // lsof 返回非0说明端口未被占用（可用）
            if !res.isSuccess {
                return (true, L("端口 \(port) 空闲可用", "Port \(port) is available"))
            } else {
                return (false, L("端口 \(port) 目前被占用，等待释放", "Port \(port) in use; waiting to be released"))
            }

        case .hostReachable:
            guard !param.isEmpty else {
                return (false, L("未指定目标主机", "Target host not specified"))
            }
            let cmd = "ping -c 1 -t 2 '\(param)' >/dev/null 2>&1 || curl -sI -m 2 '\(param)' >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return res.isSuccess ? (true, L("目标主机 \(param) 可达", "Host \(param) reachable")) : (false, L("等待主机 \(param) 网络可达", "Waiting for host \(param)"))

        case .custom:
            guard !param.isEmpty else {
                return (true, L("未配置命令，默认满足", "No command configured; treated as satisfied"))
            }
            let res = await ProcessRunner.run(command: param, timeout: 5)
            if res.isSuccess {
                return (true, L("自定义检测通过", "Custom check passed"))
            } else {
                return (false, L("等待自定义条件满足 (退出码: \(res.exitCode))", "Waiting for custom condition (exit code: \(res.exitCode))"))
            }
        }
    }
}
