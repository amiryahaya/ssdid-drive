defmodule SecureSharingWeb.Dev.EmailPreviewController do
  @moduledoc """
  Controller for sending test emails in development.
  Only compiled when dev_routes is enabled.
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Emails.NotificationEmail
  alias SecureSharing.Mailer

  def send_all(conn, _params) do
    # Mock data for testing
    test_user = %{
      id: "test-user-id",
      email: "user@example.com",
      display_name: "John Doe"
    }

    test_tenant = %{
      id: "test-tenant-id",
      name: "Acme Corporation",
      slug: "acme"
    }

    test_inviter = %{
      id: "inviter-id",
      email: "admin@example.com",
      display_name: "Jane Admin"
    }

    # Send all test emails
    emails_sent = [
      {"Verification Email",
       fn -> NotificationEmail.verification_email(test_user, "test-verification-token-12345") end},
      {"Welcome Email", fn -> NotificationEmail.welcome_email(test_user) end},
      {"Password Changed",
       fn ->
         NotificationEmail.password_changed_email(test_user, %{
           changed_at: DateTime.utc_now(),
           ip_address: "192.168.1.100",
           device: "Chrome on Windows"
         })
       end},
      {"Forgot Password (with recovery)",
       fn -> NotificationEmail.forgot_password_email(test_user, true) end},
      {"Forgot Password (without recovery)",
       fn ->
         NotificationEmail.forgot_password_email(
           %{test_user | email: "norecovery@example.com", display_name: "No Recovery User"},
           false
         )
       end},
      {"New Device Login",
       fn ->
         NotificationEmail.new_device_login_email(
           test_user,
           %{name: "Pixel 8 Pro", platform: "Android 14"},
           %{
             login_at: DateTime.utc_now(),
             ip_address: "203.0.113.50",
             location: "Kuala Lumpur, Malaysia"
           }
         )
       end},
      {"Tenant Invitation",
       fn -> NotificationEmail.invitation_email(test_user, test_tenant, test_inviter) end},
      {"Share Notification",
       fn ->
         NotificationEmail.share_notification_email(
           test_user,
           test_inviter,
           "file",
           "Q4 Financial Report.pdf"
         )
       end},
      {"Share Expiry Warning",
       fn ->
         NotificationEmail.share_expiry_warning_email(
           test_user,
           test_inviter,
           "folder",
           "Project Documents",
           DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second)
         )
       end},
      {"Recovery Request",
       fn ->
         NotificationEmail.recovery_request_email(
           %{test_user | email: "trustee@example.com", display_name: "Trusted Friend"},
           %{id: "requester-id", email: "needshelp@example.com", display_name: "Needs Help User"}
         )
       end},
      {"Recovery Complete", fn -> NotificationEmail.recovery_complete_email(test_user) end}
    ]

    results =
      Enum.map(emails_sent, fn {name, email_fn} ->
        email = email_fn.()

        case Mailer.deliver(email) do
          {:ok, _} -> %{name: name, status: "sent"}
          {:error, reason} -> %{name: name, status: "failed", error: inspect(reason)}
        end
      end)

    json(conn, %{
      message: "Test emails sent! View them at /dev/mailbox",
      emails: results
    })
  end
end
