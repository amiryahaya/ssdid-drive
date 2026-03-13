import Foundation
import Combine

/// Delegate for activity view model coordinator events
protocol ActivityViewModelCoordinatorDelegate: AnyObject {
    func activityDidSelectResource(resourceId: String, resourceName: String)
}

/// View model for the activity log screen
@MainActor
final class ActivityViewModel: BaseViewModel {

    // MARK: - Properties

    private let activityRepository: ActivityRepository

    weak var coordinatorDelegate: ActivityViewModelCoordinatorDelegate?

    @Published var activities: [FileActivity] = []
    @Published var selectedFilter: String = "all"
    @Published var hasMorePages: Bool = false

    private var currentPage = 1
    private let pageSize = 20
    private var isLoadingMore = false

    // MARK: - Filter Options

    static let filters: [(label: String, value: String)] = [
        ("All", "all"),
        ("Uploads", "uploads"),
        ("Downloads", "downloads"),
        ("Shares", "shares"),
        ("Deletes", "deletes"),
        ("Folders", "folders")
    ]

    // MARK: - Initialization

    init(activityRepository: ActivityRepository) {
        self.activityRepository = activityRepository
        super.init()
    }

    // MARK: - Data Loading

    func loadActivity() {
        currentPage = 1
        isLoading = true
        clearError()

        Task {
            do {
                let eventType = eventTypeForFilter(selectedFilter)
                let response = try await activityRepository.getActivity(
                    page: currentPage,
                    pageSize: pageSize,
                    eventType: eventType
                )
                self.activities = response.items
                self.hasMorePages = response.items.count >= pageSize && response.total > response.items.count
                self.isLoading = false
            } catch {
                handleError(error)
            }
        }
    }

    func loadMoreIfNeeded(currentItem: FileActivity) {
        guard !isLoadingMore,
              hasMorePages,
              let index = activities.firstIndex(where: { $0.id == currentItem.id }),
              index >= activities.count - 5 else { return }

        isLoadingMore = true
        currentPage += 1

        Task {
            do {
                let eventType = eventTypeForFilter(selectedFilter)
                let response = try await activityRepository.getActivity(
                    page: currentPage,
                    pageSize: pageSize,
                    eventType: eventType
                )
                self.activities.append(contentsOf: response.items)
                self.hasMorePages = response.items.count >= pageSize && response.total > self.activities.count
                self.isLoadingMore = false
            } catch {
                self.currentPage -= 1
                self.isLoadingMore = false
                handleError(error)
            }
        }
    }

    // MARK: - Filtering

    func setFilter(_ filter: String) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        loadActivity()
    }

    // MARK: - Navigation

    func selectActivity(_ activity: FileActivity) {
        coordinatorDelegate?.activityDidSelectResource(
            resourceId: activity.resourceId,
            resourceName: activity.resourceName
        )
    }

    // MARK: - Section Grouping

    /// Group activities by date section (Today / Yesterday / Earlier)
    func groupedActivities() -> [(title: String, activities: [FileActivity])] {
        let calendar = Calendar.current
        var today: [FileActivity] = []
        var yesterday: [FileActivity] = []
        var earlier: [FileActivity] = []

        for activity in activities {
            if calendar.isDateInToday(activity.createdAt) {
                today.append(activity)
            } else if calendar.isDateInYesterday(activity.createdAt) {
                yesterday.append(activity)
            } else {
                earlier.append(activity)
            }
        }

        var sections: [(title: String, activities: [FileActivity])] = []
        if !today.isEmpty { sections.append(("Today", today)) }
        if !yesterday.isEmpty { sections.append(("Yesterday", yesterday)) }
        if !earlier.isEmpty { sections.append(("Earlier", earlier)) }
        return sections
    }

    // MARK: - Helpers

    private func eventTypeForFilter(_ filter: String) -> String? {
        switch filter {
        case "uploads": return "file.uploaded"
        case "downloads": return "file.downloaded"
        case "shares": return "file.shared"
        case "deletes": return "file.deleted"
        case "folders": return "folder.created"
        default: return nil
        }
    }
}
