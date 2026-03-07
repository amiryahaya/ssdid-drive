import UIKit
import Combine

/// Delegate for PII chat coordinator events
protocol PiiChatCoordinatorDelegate: AnyObject {
    // Add delegate methods if needed for cross-tab navigation
}

/// Coordinator for PII chat flow
final class PiiChatCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: PiiChatCoordinatorDelegate?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Start

    override func start() {
        showConversationList()
    }

    // MARK: - Navigation

    func showConversationList() {
        let viewModel = ConversationListViewModel(
            piiRepository: container.piiRepository
        )
        viewModel.coordinatorDelegate = self

        let conversationListVC = ConversationListViewController(viewModel: viewModel)
        navigationController.setViewControllers([conversationListVC], animated: false)
    }

    func showChat(conversation: PiiConversation) {
        let viewModel = ChatViewModel(
            piiRepository: container.piiRepository,
            conversation: conversation
        )
        viewModel.coordinatorDelegate = self

        let chatVC = ChatViewController(viewModel: viewModel)
        navigationController.pushViewController(chatVC, animated: true)
    }

    func showNewConversation() {
        let viewModel = NewConversationViewModel(
            piiRepository: container.piiRepository
        )
        viewModel.coordinatorDelegate = self

        let newConversationVC = NewConversationViewController(viewModel: viewModel)
        let navController = UINavigationController(rootViewController: newConversationVC)

        if let sheet = navController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(navController, animated: true)
    }
}

// MARK: - ConversationListViewModelCoordinatorDelegate

extension PiiChatCoordinator: ConversationListViewModelCoordinatorDelegate {
    func conversationListDidSelectConversation(_ conversation: PiiConversation) {
        showChat(conversation: conversation)
    }

    func conversationListDidRequestNewConversation() {
        showNewConversation()
    }
}

// MARK: - ChatViewModelCoordinatorDelegate

extension PiiChatCoordinator: ChatViewModelCoordinatorDelegate {
    // Add delegate methods if needed
}

// MARK: - NewConversationViewModelCoordinatorDelegate

extension PiiChatCoordinator: NewConversationViewModelCoordinatorDelegate {
    func newConversationDidCreate(_ conversation: PiiConversation) {
        navigationController.dismiss(animated: true) { [weak self] in
            self?.showChat(conversation: conversation)
        }
    }

    func newConversationDidCancel() {
        navigationController.dismiss(animated: true)
    }
}
