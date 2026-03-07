# Email Preview Script
# Run with: mix run test/support/email_preview.exs
# Then view emails at: http://localhost:4000/dev/mailbox

alias SecureSharing.Emails.NotificationEmail
alias SecureSharing.Mailer

# Mock user for testing
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

IO.puts("Sending test emails to Swoosh mailbox...")
IO.puts("View them at: http://localhost:4000/dev/mailbox")
IO.puts("")

# 1. Email Verification
IO.puts("1. Sending verification email...")

NotificationEmail.verification_email(test_user, "test-verification-token-12345")
|> Mailer.deliver()

# 2. Welcome Email
IO.puts("2. Sending welcome email...")

NotificationEmail.welcome_email(test_user)
|> Mailer.deliver()

# 3. Password Changed
IO.puts("3. Sending password changed email...")

NotificationEmail.password_changed_email(test_user, %{
  changed_at: DateTime.utc_now(),
  ip_address: "192.168.1.100",
  device: "Chrome on Windows"
})
|> Mailer.deliver()

# 4. Forgot Password (with recovery)
IO.puts("4. Sending forgot password email (with recovery)...")

NotificationEmail.forgot_password_email(test_user, true)
|> Mailer.deliver()

# 5. Forgot Password (without recovery)
IO.puts("5. Sending forgot password email (without recovery)...")
forgot_user = %{test_user | email: "norecovery@example.com", display_name: "No Recovery User"}

NotificationEmail.forgot_password_email(forgot_user, false)
|> Mailer.deliver()

# 6. New Device Login
IO.puts("6. Sending new device login email...")

NotificationEmail.new_device_login_email(
  test_user,
  %{name: "Pixel 8 Pro", platform: "Android 14"},
  %{
    login_at: DateTime.utc_now(),
    ip_address: "203.0.113.50",
    location: "Kuala Lumpur, Malaysia"
  }
)
|> Mailer.deliver()

# 7. Tenant Invitation
IO.puts("7. Sending tenant invitation email...")

NotificationEmail.invitation_email(test_user, test_tenant, test_inviter)
|> Mailer.deliver()

# 8. Share Notification
IO.puts("8. Sending share notification email...")

NotificationEmail.share_notification_email(
  test_user,
  test_inviter,
  "file",
  "Q4 Financial Report.pdf"
)
|> Mailer.deliver()

# 9. Share Expiry Warning
IO.puts("9. Sending share expiry warning email...")

NotificationEmail.share_expiry_warning_email(
  test_user,
  test_inviter,
  "folder",
  "Project Documents",
  DateTime.add(DateTime.utc_now(), 24 * 60 * 60, :second)
)
|> Mailer.deliver()

# 10. Recovery Request (to trustee)
IO.puts("10. Sending recovery request email...")
trustee = %{test_user | email: "trustee@example.com", display_name: "Trusted Friend"}
requester = %{id: "requester-id", email: "needshelp@example.com", display_name: "Needs Help User"}

NotificationEmail.recovery_request_email(trustee, requester)
|> Mailer.deliver()

# 11. Recovery Complete
IO.puts("11. Sending recovery complete email...")

NotificationEmail.recovery_complete_email(test_user)
|> Mailer.deliver()

IO.puts("")
IO.puts("✅ All 11 test emails sent!")
IO.puts("📧 View them at: http://localhost:4000/dev/mailbox")
