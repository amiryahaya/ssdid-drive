import Foundation
import Combine

/// Delegate for conversation list view model coordinator events
protocol ConversationListViewModelCoordinatorDelegate: AnyObject {
    func conversationListDidSelectConversation(_ conversation: PiiConversation)
    func conversationListDidRequestNewConversation()
}

/// View model for conversation list screen
final class ConversationListViewModel: BaseViewModel {

    // MARK: - Properties

    private let piiRepository: PiiRepository
    weak var coordinatorDelegate: ConversationListViewModelCoordinatorDelegate?

    @Published var conversations: [PiiConversation] = []
    @Published var isRefreshing: Bool = false
    @Published var isEmpty: Bool = true

    /// Track active tasks for proper cancellation
    private var activeTasks = Set<Task<Void, Never>>()
    private let taskLock = NSLock()

    // MARK: - Initialization

    init(piiRepository: PiiRepository) {
        self.piiRepository = piiRepository
        super.init()
        loadConversations()
    }

    deinit {
        taskLock.lock()
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        taskLock.unlock()
    }

    // MARK: - Task Management

    private func trackTask(_ operation: @escaping @Sendable () async -> Void) {
        let task = Task { [weak self] in
            await operation()
            self?.removeTask(Task { })
        }

        taskLock.lock()
        activeTasks.insert(task)
        taskLock.unlock()

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

    // MARK: - Data Loading

    func loadConversations() {
        isLoading = true
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                let conversations = try await self.piiRepository.listConversations()
                // Sort by created_at descending (newest first)
                let sorted = conversations.sorted {
                    $0.createdAt > $1.createdAt
                }
                await MainActor.run { [weak self] in
                    self?.conversations = sorted
                    self?.isEmpty = sorted.isEmpty
                    self?.isLoading = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(error)
                    self?.isLoading = false
                }
            }
        }
    }

    func refreshConversations() {
        isRefreshing = true
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                let conversations = try await self.piiRepository.listConversations()
                let sorted = conversations.sorted {
                    $0.createdAt > $1.createdAt
                }
                await MainActor.run { [weak self] in
                    self?.conversations = sorted
                    self?.isEmpty = sorted.isEmpty
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

    func selectConversation(_ conversation: PiiConversation) {
        coordinatorDelegate?.conversationListDidSelectConversation(conversation)
    }

    func requestNewConversation() {
        coordinatorDelegate?.conversationListDidRequestNewConversation()
    }

    func deleteConversation(_ conversation: PiiConversation) {
        // Remove from local list (server delete can be implemented later)
        conversations.removeAll { $0.id == conversation.id }
        isEmpty = conversations.isEmpty
    }
}
