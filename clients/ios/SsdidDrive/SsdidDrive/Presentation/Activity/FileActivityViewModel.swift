import Foundation
import Combine

/// View model for per-file activity log screen
@MainActor
final class FileActivityViewModel: BaseViewModel {

    // MARK: - Properties

    private let activityRepository: ActivityRepository
    let resourceId: String
    let resourceName: String

    @Published var activities: [FileActivity] = []
    @Published var hasMorePages: Bool = false

    private var currentPage = 1
    private let pageSize = 20
    private var isLoadingMore = false

    // MARK: - Initialization

    init(activityRepository: ActivityRepository, resourceId: String, resourceName: String) {
        self.activityRepository = activityRepository
        self.resourceId = resourceId
        self.resourceName = resourceName
        super.init()
    }

    // MARK: - Data Loading

    func loadActivity() {
        currentPage = 1
        isLoading = true
        clearError()

        Task {
            do {
                let response = try await activityRepository.getResourceActivity(
                    resourceId: resourceId,
                    page: currentPage,
                    pageSize: pageSize
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
                let response = try await activityRepository.getResourceActivity(
                    resourceId: resourceId,
                    page: currentPage,
                    pageSize: pageSize
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
}
