import Foundation
import AppKit

public final class PreconditionChecker {
    @MainActor private static var cachedWifiDev: String? = nil

    @MainActor
    private static func getWifiDevice() async -> String {
        if let dev = cachedWifiDev { return dev }
        let findDevCmd = "networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}'"
        let devRes = await ProcessRunner.run(command: findDevCmd, timeout: 2)
        let dev = devRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = dev.isEmpty ? "en0" : dev
        cachedWifiDev = resolved
        return resolved
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
            return res.isSuccess ? (true, L("互联网已连通", "Internet connected")) : (false, L("等待外网连接", "Waiting for internet"))

        case .networkDisconnected:
            let cmd = "curl -sI -m 2 https://captive.apple.com/hotspot-detect.html >/dev/null 2>&1 || ping -c 1 -t 2 223.5.5.5 >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return !res.isSuccess ? (true, L("当前处于离线模式", "Currently offline")) : (false, L("等待网络断开", "Waiting for network to disconnect"))

        case .wifiConnected:
            let targetDev = await getWifiDevice()
            let wifiCmd = "networksetup -getairportnetwork \(targetDev) 2>/dev/null"
            let wifiRes = await ProcessRunner.run(command: wifiCmd, timeout: 2)
            if wifiRes.output.contains("Current Wi-Fi Network:") {
                let parts = wifiRes.output.components(separatedBy: "Current Wi-Fi Network:")
                let currentSSID = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !param.isEmpty {
                    if currentSSID.localizedCaseInsensitiveContains(param) {
                        return (true, L("已连接指定 Wi-Fi: \(currentSSID)", "Connected to specified Wi-Fi: \(currentSSID)"))
                    } else {
                        return (false, L("当前为 \(currentSSID)，等待连接指定 Wi-Fi: \(param)", "Currently on \(currentSSID); waiting for \(param)"))
                    }
                } else {
                    return (true, L("已连接 Wi-Fi: \(currentSSID)", "Wi-Fi connected: \(currentSSID)"))
                }
            } else {
                return (false, L("等待连接 Wi-Fi", "Waiting for Wi-Fi"))
            }

        case .wifiDisconnected:
            let targetDev = await getWifiDevice()
            let wifiCmd = "networksetup -getairportnetwork \(targetDev) 2>/dev/null"
            let wifiRes = await ProcessRunner.run(command: wifiCmd, timeout: 2)
            if !wifiRes.output.contains("Current Wi-Fi Network:") {
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
