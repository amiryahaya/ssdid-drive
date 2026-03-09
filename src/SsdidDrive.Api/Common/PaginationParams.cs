namespace SsdidDrive.Api.Common;

public record PaginationParams(int Page = 1, int PageSize = 50, string? Search = null)
{
    public int Skip => (Math.Max(1, Page) - 1) * Take;
    public int Take => Math.Clamp(PageSize, 1, 100);
}

public record PagedResponse<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize)
{
    public int TotalPages => (int)Math.Ceiling((double)Total / PageSize);
}
