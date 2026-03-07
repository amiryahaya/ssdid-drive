import Foundation
import Combine

/// Delegate for notification list view model coordinator events
protocol NotificationListViewModelCoordinatorDelegate: AnyObject {
    func notificationListDidSelectNotification(_ notification: AppNotification)
}

/// View model for notification list screen
final class NotificationListViewModel: BaseViewModel {

    // MARK: - Types

    struct Section: Hashable {
        let title: String
        let notifications: [AppNotification]

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
        }

        static func == (lhs: Section, rhs: Section) -> Bool {
            lhs.title == rhs.title && lhs.notifications == rhs.notifications
        }
    }

    // MARK: - Properties

    private let notificationRepository: NotificationRepository
    weak var coordinatorDelegate: NotificationListViewModelCoordinatorDelegate?

    @Published var sections: [Section] = []
    @Published var unreadCount: Int = 0
    @Published var isEmpty: Bool = true
    @Published var isRefreshing: Bool = false

    /// Track active tasks for proper cancellation on dealloc
    private var activeTasks = Set<Task<Void, Never>>()
    private let taskLock = NSLock()

    // MARK: - Initialization

    init(notificationRepository: NotificationRepository) {
        self.notificationRepository = notificationRepository
        super.init()
        setupBindings()
    }

    deinit {
        // Cancel all active tasks when ViewModel is deallocated
        taskLock.lock()
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        taskLock.unlock()
    }

    // MARK: - Task Management

    /// Creates and tracks a task, automatically removing it when complete
    private func trackTask(_ operation: @escaping @Sendable () async -> Void) {
        let task = Task { [weak self] in
            await operation()
            self?.removeTask(Task { })
        }

        taskLock.lock()
        activeTasks.insert(task)
        taskLock.unlock()

        // Store actual task reference for removal
        Task { [weak self] in
            await task.value
            self?.removeTask(task)
        }
    }

    private func removeTask(_ task: Task<Void, Never>) {
        taskLock.lock()
        activeTasks.remove(task)
        taskLock.unlock()
    }

    // MARK: - Setup

    private func setupBindings() {
        notificationRepository.observeNotifications()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notifications in
                self?.groupNotificationsByDate(notifications)
                self?.isEmpty = notifications.isEmpty
            }
            .store(in: &cancellables)

        notificationRepository.observeUnreadCount()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.unreadCount = count
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading

    func refreshNotifications() {
        isRefreshing = true
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                // Force refresh by getting notifications directly
                let _ = try await self.notificationRepository.getNotifications()
                await MainActor.run { [weak self] in
                    self?.isRefreshing = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(error)
                    self?.isRefreshing = false
                }
            }
        }
    }

    // MARK: - Actions

    func markAsRead(_ notification: AppNotification) {
        guard notification.isUnread else { return }
        let notificationId = notification.id
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                try await self.notificationRepository.markAsRead(notificationId: notificationId)
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(error)
                }
            }
        }
    }

    func markAllAsRead() {
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                try await self.notificationRepository.markAllAsRead()
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(error)
                }
            }
        }
    }

    func deleteNotification(_ notification: AppNotification) {
        let notificationId = notification.id
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                try await self.notificationRepository.deleteNotification(notificationId: notificationId)
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(error)
                }
            }
        }
    }

    func deleteAllNotifications() {
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                try await self.notificationRepository.deleteAllNotifications()
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(error)
                }
            }
        }
    }

    func selectNotification(_ notification: AppNotification) {
        // Mark as read when selected
        if notification.isUnread {
            markAsRead(notification)
        }
        // Navigate via coordinator
        coordinatorDelegate?.notificationListDidSelectNotification(notification)
    }

    // MARK: - Private

    private func groupNotificationsByDate(_ notifications: [AppNotification]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            sections = []
            return
        }

        var todayNotifications: [AppNotification] = []
        var yesterdayNotifications: [AppNotification] = []
        var earlierNotifications: [AppNotification] = []

        for notification in notifications {
            let notificationDay = calendar.startOfDay(for: notification.createdAt)

            if notificationDay == today {
                todayNotifications.append(notification)
            } else if notificationDay == yesterday {
                yesterdayNotifications.append(notification)
            } else {
                earlierNotifications.append(notification)
            }
        }

        var newSections: [Section] = []
        if !todayNotifications.isEmpty {
            newSections.append(Section(
                title: NSLocalizedString("notification.section.today", value: "Today", comment: "Today section header"),
                notifications: todayNotifications
            ))
        }
        if !yesterdayNotifications.isEmpty {
            newSections.append(Section(
                title: NSLocalizedString("notification.section.yesterday", value: "Yesterday", comment: "Yesterday section header"),
                notifications: yesterdayNotifications
            ))
        }
        if !earlierNotifications.isEmpty {
            newSections.append(Section(
                title: NSLocalizedString("notification.section.earlier", value: "Earlier", comment: "Earlier section header"),
                notifications: earlierNotifications
            ))
        }

        sections = newSections
    }

    // MARK: - Computed Properties

    var hasUnread: Bool {
        unreadCount > 0
    }

    var totalCount: Int {
        sections.reduce(0) { $0 + $1.notifications.count }
    }
}
