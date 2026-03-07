import Foundation
import Combine

/// Delegate for new conversation view model coordinator events
protocol NewConversationViewModelCoordinatorDelegate: AnyObject {
    func newConversationDidCreate(_ conversation: PiiConversation)
    func newConversationDidCancel()
}

/// View model for new conversation screen
final class NewConversationViewModel: BaseViewModel {

    // MARK: - Properties

    private let piiRepository: PiiRepository
    weak var coordinatorDelegate: NewConversationViewModelCoordinatorDelegate?

    @Published var title: String = ""
    @Published var selectedProviderId: String = "openai"
    @Published var selectedModel: String = "gpt-4o"
    @Published var isCreating: Bool = false

    // MARK: - Initialization

    init(piiRepository: PiiRepository) {
        self.piiRepository = piiRepository
        super.init()
    }

    // MARK: - Computed Properties

    var providers: [LlmProvider] {
        LlmProvider.providers
    }

    var selectedProvider: LlmProvider? {
        providers.first { $0.id == selectedProviderId }
    }

    var availableModels: [String] {
        selectedProvider?.models ?? []
    }

    // MARK: - Actions

    func selectProvider(_ providerId: String) {
        selectedProviderId = providerId
        // Reset model to first available
        if let provider = providers.first(where: { $0.id == providerId }),
           let firstModel = provider.models.first {
            selectedModel = firstModel
        }
    }

    func selectModel(_ model: String) {
        selectedModel = model
    }

    func createConversation() {
        isCreating = true

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let conversation = try await self.piiRepository.createConversation(
                    title: self.title.isEmpty ? nil : self.title,
                    llmProvider: self.selectedProviderId,
                    llmModel: self.selectedModel
                )
                self.isCreating = false
                self.coordinatorDelegate?.newConversationDidCreate(conversation)
            } catch {
                self.isCreating = false
                self.handleError(error)
            }
        }
    }

    func cancel() {
        coordinatorDelegate?.newConversationDidCancel()
    }
}
