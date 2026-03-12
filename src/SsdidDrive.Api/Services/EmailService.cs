using System.Net;
using Resend;

namespace SsdidDrive.Api.Services;

public interface IEmailService
{
    Task SendInvitationAsync(string toEmail, string tenantName, string role, string shortCode, string? message);
}

public sealed class NullEmailService : IEmailService
{
    public Task SendInvitationAsync(string toEmail, string tenantName, string role, string shortCode, string? message)
        => Task.CompletedTask;
}

public class EmailService : IEmailService
{
    private readonly IResend _resend;
    private readonly string _fromAddress;
    private readonly string _serviceUrl;
    private readonly ILogger<EmailService> _logger;

    public EmailService(IResend resend, IConfiguration config, ILogger<EmailService> logger)
    {
        _resend = resend;
        _fromAddress = config["Email:From"] ?? "noreply@ssdid.my";
        _serviceUrl = config["Ssdid:ServiceUrl"] ?? "https://drive.ssdid.my";
        _logger = logger;
    }

    public async Task SendInvitationAsync(string toEmail, string tenantName, string role, string shortCode, string? message)
    {
        // HTML-encode all user-controlled values to prevent XSS/injection in email
        var safeTenantName = WebUtility.HtmlEncode(tenantName);
        var safeRole = WebUtility.HtmlEncode(role);
        var safeShortCode = WebUtility.HtmlEncode(shortCode);
        var safeMessage = string.IsNullOrWhiteSpace(message) ? null : WebUtility.HtmlEncode(message);
        var inviteUrl = $"{_serviceUrl}/invite/{Uri.EscapeDataString(shortCode)}";

        var html = $"""
            <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 0;">
                <h2 style="color: #111827; margin-bottom: 8px;">You've been invited to SSDID Drive</h2>
                <p style="color: #6b7280; font-size: 15px;">
                    You've been invited to join <strong style="color: #111827;">{safeTenantName}</strong> as <strong style="color: #111827;">{safeRole}</strong>.
                </p>
                {(safeMessage is null ? "" : $"""<p style="color: #6b7280; font-size: 14px; font-style: italic; border-left: 3px solid #e5e7eb; padding-left: 12px;">"{safeMessage}"</p>""")}
                <div style="background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 16px; margin: 24px 0; text-align: center;">
                    <p style="color: #6b7280; font-size: 13px; margin: 0 0 8px;">Your invite code</p>
                    <p style="font-size: 24px; font-weight: bold; letter-spacing: 2px; color: #111827; margin: 0; font-family: monospace;">{safeShortCode}</p>
                </div>
                <div style="text-align: center; margin: 24px 0;">
                    <a href="{inviteUrl}" style="display: inline-block; background: #2563eb; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 500; font-size: 15px;">Open Invitation</a>
                </div>
                <p style="color: #9ca3af; font-size: 13px; text-align: center;">
                    Or enter the code manually in the SSDID Drive app.
                </p>
                <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;">
                <p style="color: #9ca3af; font-size: 12px; text-align: center;">
                    SSDID Drive — Post-quantum secure file storage
                </p>
            </div>
            """;

        var emailMessage = new EmailMessage
        {
            From = _fromAddress,
            Subject = $"You've been invited to {safeTenantName} on SSDID Drive"
        };
        emailMessage.To.Add(toEmail);
        emailMessage.HtmlBody = html;

        try
        {
            await _resend.EmailSendAsync(emailMessage);
            _logger.LogInformation("Invitation email sent to {Email} for tenant {Tenant}", toEmail, tenantName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send invitation email to {Email}", toEmail);
            // Don't throw — invitation is created regardless of email delivery
        }
    }
}
