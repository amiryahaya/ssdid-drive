import Foundation
import Combine

/// Delegate for chat view model coordinator events
protocol ChatViewModelCoordinatorDelegate: AnyObject {
    // Add delegate methods if needed
}

/// View model for chat screen
final class ChatViewModel: BaseViewModel {

    // MARK: - Properties

    private let piiRepository: PiiRepository
    weak var coordinatorDelegate: ChatViewModelCoordinatorDelegate?

    @Published var conversation: PiiConversation
    @Published var messages: [ChatMessage] = []
    @Published var isSending: Bool = false
    @Published var isKemRegistered: Bool = false

    /// Track active tasks for proper cancellation
    private var activeTasks = Set<Task<Void, Never>>()
    private let taskLock = NSLock()

    // MARK: - Initialization

    init(piiRepository: PiiRepository, conversation: PiiConversation) {
        self.piiRepository = piiRepository
        self.conversation = conversation
        self.isKemRegistered = conversation.hasKemKeysRegistered || piiRepository.hasKemKeysLoaded()
        super.init()
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

    // MARK: - Actions

    func sendMessage(_ text: String) {
        let conversationId = conversation.id

        // Auto-register KEM keys if not registered
        if !isKemRegistered {
            registerKemKeysAndSend(text, conversationId: conversationId)
            return
        }

        sendMessageInternal(text, conversationId: conversationId)
    }

    private func registerKemKeysAndSend(_ text: String, conversationId: String) {
        isLoading = true
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                _ = try await self.piiRepository.registerKemKeys(
                    conversationId: conversationId,
                    includeKazKem: true
                )
                await MainActor.run { [weak self] in
                    self?.isKemRegistered = true
                    self?.isLoading = false
                    self?.sendMessageInternal(text, conversationId: conversationId)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(error)
                    self?.isLoading = false
                }
            }
        }
    }

    private func sendMessageInternal(_ text: String, conversationId: String) {
        // Add optimistic user message
        let tempMessage = ChatMessage(
            id: "temp-\(Date().timeIntervalSince1970)",
            conversationId: conversationId,
            role: .user,
            content: text,
            tokenizedContent: nil,
            tokensDetected: 0,
            createdAt: Date()
        )
        messages.append(tempMessage)

        isSending = true
        trackTask { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await self.piiRepository.ask(
                    conversationId: conversationId,
                    message: text,
                    contextFiles: nil
                )

                await MainActor.run { [weak self] in
                    guard let self = self else { return }

                    // Remove temp message
                    self.messages.removeAll { $0.id.hasPrefix("temp-") }

                    // Parse created_at date
                    let createdAt = self.parseDate(response.createdAt) ?? Date()

                    // Add real user message
                    let userMessage = ChatMessage(
                        id: response.userMessageId,
                        conversationId: conversationId,
                        role: .user,
                        content: text,
                        tokenizedContent: nil,
                        tokensDetected: response.tokensDetected,
                        createdAt: createdAt
                    )
                    self.messages.append(userMessage)

                    // Add assistant response
                    let assistantMessage = ChatMessage(
                        id: response.assistantMessageId,
                        conversationId: conversationId,
                        role: .assistant,
                        content: response.content,
                        tokenizedContent: response.tokenizedContent,
                        tokensDetected: response.tokensDetected,
                        createdAt: createdAt
                    )
                    self.messages.append(assistantMessage)

                    self.isSending = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    // Remove optimistic message on error
                    self.messages.removeAll { $0.id.hasPrefix("temp-") }
                    self.handleError(error)
                    self.isSending = false
                }
            }
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }

    // MARK: - Computed Properties

    var providerName: String {
        LlmProvider.provider(for: conversation.llmProvider)?.name ?? conversation.llmProvider
    }
}
