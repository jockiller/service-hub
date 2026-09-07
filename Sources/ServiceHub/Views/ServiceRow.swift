import SwiftUI

@MainActor
struct ServiceRow: View {
    let service: Service
    @ObservedObject var supervisor = Supervisor.shared

    var body: some View {
        HStack(spacing: 10) {
            ServiceIconView(service: service, size: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Circle()
                        .fill(currentStatus.color)
                        .frame(width: 7, height: 7)
                    Text(currentStatus.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if supervisor.isBusy[service.id] == true {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentStatus: ServiceStatus {
        supervisor.statuses[service.id] ?? .unknown
    }
}
