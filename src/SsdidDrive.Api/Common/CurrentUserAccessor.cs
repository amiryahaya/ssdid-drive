using SsdidDrive.Api.Data.Entities;

namespace SsdidDrive.Api.Common;

public class CurrentUserAccessor
{
    public Guid UserId { get; set; }
    public string Did { get; set; } = default!;
    public User? User { get; set; }
    public string? SessionToken { get; set; }
    public Data.Entities.SystemRole? SystemRole { get; set; }
}
