import Foundation
import Combine
import AppKit

@MainActor
final class MenuBarViewModel: ObservableObject {

    // MARK: - Published State

    @Published var recentFiles: [RecentFile] = []
    @Published var syncStatus: SharedDefaults.SyncStatus = .offline
    @Published var lastSyncDate: Date?
    @Published var isAuthenticated: Bool = false
    @Published var userDisplayName: String?

    // MARK: - Private

    private let sharedDefaults = SharedDefaults.shared
    private var cancellables = Set<AnyCancellable>()
    private var distributedObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
        refresh()
        startListening()
    }

    deinit {
        if let observer = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Listening (DistributedNotificationCenter + fallback timer)

    private func startListening() {
        // Primary: respond immediately to writes from the main app
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init(SharedDefaults.changeNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        // Fallback: poll every 30s in case a notification is missed
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        recentFiles = sharedDefaults.readRecentFiles()
        syncStatus = sharedDefaults.readSyncStatus()
        lastSyncDate = sharedDefaults.readLastSyncDate()
        isAuthenticated = sharedDefaults.readIsAuthenticated()
        userDisplayName = sharedDefaults.readUserDisplayName()
    }

    // MARK: - Actions (use pending action tokens to prevent URL scheme hijacking)

    func openFile(_ file: RecentFile) {
        let token = UUID().uuidString
        let action = SharedDefaults.PendingAction(
            type: file.isFolder ? .openFolder : .openFile,
            resourceId: file.id,
            createdAt: Date()
        )
        sharedDefaults.writePendingAction(token: token, action: action)
        guard let url = URL(string: "securesharing://action/\(token)") else { return }
        NSWorkspace.shared.open(url)
    }

    func requestUpload() {
        let token = UUID().uuidString
        let action = SharedDefaults.PendingAction(
            type: .importFile,
            resourceId: nil,
            createdAt: Date()
        )
        sharedDefaults.writePendingAction(token: token, action: action)
        guard let url = URL(string: "securesharing://action/\(token)") else { return }
        NSWorkspace.shared.open(url)
    }

    func openMainApp() {
        guard let url = URL(string: "securesharing://") else { return }
        NSWorkspace.shared.open(url)
    }

    func quitHelper() {
        NSApplication.shared.terminate(nil)
    }
}
