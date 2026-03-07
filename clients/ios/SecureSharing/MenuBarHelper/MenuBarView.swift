import SwiftUI

struct MenuBarView: View {

    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
            Divider()

            if viewModel.isAuthenticated {
                // Status
                StatusIndicatorView(
                    status: viewModel.syncStatus,
                    lastSyncDate: viewModel.lastSyncDate
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Recent files
                RecentFilesView(
                    files: viewModel.recentFiles,
                    onFileSelected: { viewModel.openFile($0) }
                )

                Divider()

                // Quick actions
                quickActions
            } else {
                notAuthenticatedView
            }

            Divider()

            // Quit
            Button(action: { viewModel.quitHelper() }) {
                Label("Quit SecureSharing Helper", systemImage: "power")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("SecureSharing")
                    .font(.headline)
                if let name = viewModel.userDisplayName {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { viewModel.requestUpload() }) {
                Label("Upload File", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button(action: { viewModel.openMainApp() }) {
                Label("Open SecureSharing", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
    }

    private var notAuthenticatedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Not signed in")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Open SecureSharing") {
                viewModel.openMainApp()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
