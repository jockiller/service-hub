import Foundation
import AppKit

public final class PreconditionChecker {
    /// 检查服务的前置条件是否满足
    public static func check(service: Service) async -> (isSatisfied: Bool, reason: String) {
        let param = service.preconditionParam?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch service.precondition {
        case .none:
            return (true, "就绪")

        // ------------------ 网络类 ------------------
        case .networkConnected:
            let cmd = "curl -sI -m 2 https://captive.apple.com/hotspot-detect.html >/dev/null 2>&1 || ping -c 1 -t 2 223.5.5.5 >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return res.isSuccess ? (true, "互联网已连通") : (false, "等待外网连接")

        case .networkDisconnected:
            let cmd = "curl -sI -m 2 https://captive.apple.com/hotspot-detect.html >/dev/null 2>&1 || ping -c 1 -t 2 223.5.5.5 >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return !res.isSuccess ? (true, "当前处于离线模式") : (false, "等待网络断开")

        case .wifiConnected:
            // 动态定位 Wi-Fi 硬件接口名 (避免写死 en0)
            let findDevCmd = "networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}'"
            let devRes = await ProcessRunner.run(command: findDevCmd, timeout: 2)
            let dev = devRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetDev = dev.isEmpty ? "en0" : dev

            let wifiCmd = "networksetup -getairportnetwork \(targetDev) 2>/dev/null"
            let wifiRes = await ProcessRunner.run(command: wifiCmd, timeout: 3)
            if wifiRes.output.contains("Current Wi-Fi Network:") {
                let parts = wifiRes.output.components(separatedBy: "Current Wi-Fi Network:")
                let currentSSID = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !param.isEmpty {
                    if currentSSID.localizedCaseInsensitiveContains(param) {
                        return (true, "已连接指定 Wi-Fi: \(currentSSID)")
                    } else {
                        return (false, "当前为 \(currentSSID)，等待连接指定 Wi-Fi: \(param)")
                    }
                } else {
                    return (true, "已连接 Wi-Fi: \(currentSSID)")
                }
            } else {
                return (false, "等待连接 Wi-Fi")
            }

        case .wifiDisconnected:
            let findDevCmd = "networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}'"
            let devRes = await ProcessRunner.run(command: findDevCmd, timeout: 2)
            let dev = devRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetDev = dev.isEmpty ? "en0" : dev

            let wifiCmd = "networksetup -getairportnetwork \(targetDev) 2>/dev/null"
            let wifiRes = await ProcessRunner.run(command: wifiCmd, timeout: 3)
            if !wifiRes.output.contains("Current Wi-Fi Network:") {
                return (true, "Wi-Fi 未连接")
            } else {
                return (false, "等待断开 Wi-Fi")
            }

        case .vpnActive:
            let cmd = "ifconfig 2>/dev/null | grep -q 'utun'"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            return res.isSuccess ? (true, "VPN / 代理虚拟网卡已就绪") : (false, "等待 VPN / 代理连接")

        // ------------------ 蓝牙类 ------------------
        case .bluetoothOn:
            let cmd = "system_profiler SPBluetoothDataType 2>/dev/null | grep -iE '(State: On|Bluetooth Power: On|Power State: 1)'"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return res.isSuccess ? (true, "蓝牙已开启") : (false, "等待蓝牙开启")

        case .bluetoothOff:
            let cmd = "system_profiler SPBluetoothDataType 2>/dev/null | grep -iE '(State: Off|Bluetooth Power: Off|Power State: 0)'"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return res.isSuccess ? (true, "蓝牙已关闭") : (false, "等待蓝牙关闭")

        case .bluetoothConnected:
            let cmd = "system_profiler SPBluetoothDataType 2>/dev/null"
            let res = await ProcessRunner.run(command: cmd, timeout: 4)
            if !param.isEmpty {
                // 检测指定设备
                if res.output.localizedCaseInsensitiveContains(param) && res.output.contains("Connected: Yes") {
                    return (true, "已连接蓝牙设备: \(param)")
                } else {
                    return (false, "等待连接蓝牙设备: \(param)")
                }
            } else {
                // 任意蓝牙设备
                if res.output.contains("Connected: Yes") {
                    return (true, "蓝牙设备已连接")
                } else {
                    return (false, "等待蓝牙设备连接")
                }
            }

        // ------------------ 电源与硬件 ------------------
        case .acPower:
            let cmd = "pmset -g batt 2>/dev/null | grep -q 'AC Power'"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            return res.isSuccess ? (true, "已连接电源适配器") : (false, "等待连接电源适配器 (插电)")

        case .onBattery:
            let cmd = "pmset -g batt 2>/dev/null | grep -q 'Battery Power'"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            return res.isSuccess ? (true, "正在使用电池供电") : (false, "等待断开电源切换至电池")

        case .externalDisplay:
            let screenCount = NSScreen.screens.count
            if screenCount > 1 {
                return (true, "已连接外接显示器 (共 \(screenCount) 块屏幕)")
            } else {
                return (false, "等待连接外接显示器")
            }

        case .volumeMounted:
            guard !param.isEmpty else {
                return (false, "未指定磁盘名称")
            }
            let targetPath = param.hasPrefix("/Volumes/") ? param : "/Volumes/\(param)"
            if FileManager.default.fileExists(atPath: targetPath) {
                return (true, "磁盘卷宗已挂载: \(targetPath)")
            } else {
                return (false, "等待磁盘挂载: \(targetPath)")
            }

        // ------------------ 高级类 ------------------
        case .portAvailable:
            guard let port = Int(param), port > 0, port <= 65535 else {
                return (false, "请指定有效端口号 (1~65535)")
            }
            let cmd = "lsof -i :\(port) >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 2)
            // lsof 返回非0说明端口未被占用（可用）
            if !res.isSuccess {
                return (true, "端口 \(port) 空闲可用")
            } else {
                return (false, "端口 \(port) 目前被占用，等待释放")
            }

        case .hostReachable:
            guard !param.isEmpty else {
                return (false, "未指定目标主机")
            }
            let cmd = "ping -c 1 -t 2 '\(param)' >/dev/null 2>&1 || curl -sI -m 2 '\(param)' >/dev/null 2>&1"
            let res = await ProcessRunner.run(command: cmd, timeout: 3)
            return res.isSuccess ? (true, "目标主机 \(param) 可达") : (false, "等待主机 \(param) 网络可达")

        case .custom:
            guard !param.isEmpty else {
                return (true, "未配置命令，默认满足")
            }
            let res = await ProcessRunner.run(command: param, timeout: 5)
            if res.isSuccess {
                return (true, "自定义检测通过")
            } else {
                return (false, "等待自定义条件满足 (退出码: \(res.exitCode))")
            }
        }
    }
}
