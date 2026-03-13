import Foundation

/// Repository protocol for file activity log operations
protocol ActivityRepository {

    /// Fetch activity logs with optional filtering
    /// - Parameters:
    ///   - page: Page number (1-based)
    ///   - pageSize: Number of items per page
    ///   - eventType: Optional event type filter (e.g. "file.uploaded")
    /// - Returns: Paginated activity response
    func getActivity(page: Int, pageSize: Int, eventType: String?) async throws -> ActivityResponse

    /// Fetch activity logs for a specific resource
    /// - Parameters:
    ///   - resourceId: ID of the file or folder
    ///   - page: Page number (1-based)
    ///   - pageSize: Number of items per page
    /// - Returns: Paginated activity response
    func getResourceActivity(resourceId: String, page: Int, pageSize: Int) async throws -> ActivityResponse
}
