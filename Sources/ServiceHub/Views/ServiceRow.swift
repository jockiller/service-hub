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

                HStack(spacing: 5) {
                    Text(service.category.shortName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(service.category.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(service.category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))

                    StatusDotView(color: currentStatus.color, size: 6.5)
                    Text(currentStatus.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(currentStatus.color)
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
