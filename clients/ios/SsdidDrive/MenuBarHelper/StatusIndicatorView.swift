import SwiftUI

struct StatusIndicatorView: View {

    let status: SharedDefaults.SyncStatus
    let lastSyncDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let date = lastSyncDate {
                    Text("Last sync: \(date, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private var dotColor: Color {
        switch status {
        case .connected: return .green
        case .syncing:   return .blue
        case .offline:   return .gray
        case .error:     return .red
        }
    }

    private var statusLabel: String {
        switch status {
        case .connected: return "Connected"
        case .syncing:   return "Syncing…"
        case .offline:   return "Offline"
        case .error:     return "Error"
        }
    }
}
