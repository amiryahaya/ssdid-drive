namespace SsdidDrive.Api.Ssdid;

/// <summary>
/// Manages SSE subscriber secrets and completion notifications for the wallet login flow.
/// Extract to Redis pub/sub-backed implementation for horizontal scaling.
/// </summary>
public interface ISseNotificationBus
{
    string CreateSubscriberSecret(string challengeId);
    bool ValidateSubscriberSecret(string challengeId, string secret);
    Task<string> WaitForCompletion(string challengeId, CancellationToken ct);
    bool NotifyCompletion(string challengeId, string sessionToken);
}
