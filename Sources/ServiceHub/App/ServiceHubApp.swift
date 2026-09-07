import SwiftUI

@main
struct ServiceHubApp: App {
    @StateObject private var store = ServiceStore.shared
    @StateObject private var supervisor = Supervisor.shared

    var body: some Scene {
        // 主程序窗口
        WindowGroup("ServiceHub", id: "main") {
            MainWindow()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }

        // 顶部菜单栏常驻图标 (MenuBarExtra)
        MenuBarExtra {
            VStack {
                Text("ServiceHub 服务概览")
                    .font(.headline)

                Divider()

                if store.services.isEmpty {
                    Text("暂无服务")
                } else {
                    ForEach(store.services) { s in
                        HStack {
                            let status = supervisor.statuses[s.id] ?? .unknown
                            Circle()
                                .fill(status.color)
                                .frame(width: 8, height: 8)
                            Text(s.name)
                            Spacer()
                            if status == .running {
                                Button("停止") {
                                    Task { await supervisor.stopService(s) }
                                }
                            } else {
                                Button("启动") {
                                    Task { await supervisor.startService(s) }
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("全部检测") {
                    Task { await supervisor.probeAllServices() }
                }

                Button("打开主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows {
                        if window.canBecomeMain {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }

                Divider()

                Button("退出 ServiceHub") {
                    NSApp.terminate(nil)
                }
            }
        } label: {
            let hasError = store.services.contains(where: { supervisor.statuses[$0.id] == .failed })
            let runningCount = store.services.filter { supervisor.statuses[$0.id] == .running }.count
            Image(systemName: hasError ? "exclamationmark.triangle.fill" : (runningCount > 0 ? "server.rack" : "circle.dotted"))
        }
    }
}
