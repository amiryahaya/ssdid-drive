defmodule SecureSharing.Emails.NotificationEmail do
  @moduledoc """
  Email templates for notifications.

  All emails include both plain text and HTML versions for maximum compatibility.

  ## Email Types

  ### Account & Authentication
  - `verification_email/2` - Email verification with token
  - `welcome_email/1` - Welcome after email verified
  - `password_changed_email/2` - Security alert when password changed
  - `forgot_password_email/2` - Guidance for account recovery

  ### Security Alerts
  - `new_device_login_email/3` - Alert when login from new device

  ### Sharing & Collaboration
  - `invitation_email/3` - Tenant/organization invitation (existing user)
  - `new_user_invitation_email/2` - Invitation for new user to join
  - `invitation_accepted_email/3` - Notification when invitation is accepted
  - `share_notification_email/4` - File/folder shared notification
  - `share_expiry_warning_email/4` - Share expiring soon

  ### Recovery
  - `recovery_request_email/2` - Request sent to trustees
  - `recovery_complete_email/1` - Recovery finished notification
  """
  import Swoosh.Email

  @from_email "noreply@securesharing.example"
  @from_name "SecureSharing"
  @app_url "https://securesharing.example"

  # ============================================================================
  # Account & Authentication Emails
  # ============================================================================

  @doc """
  Create an email verification email with a verification link.
  """
  def verification_email(user, verification_token) do
    verification_url = "#{@app_url}/verify-email?token=#{verification_token}"

    new()
    |> to({user.display_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Verify your SecureSharing email address")
    |> text_body(verification_text(user, verification_url))
    |> html_body(verification_html(user, verification_url))
  end

  @doc """
  Create a welcome email after successful email verification.
  """
  def welcome_email(user) do
    new()
    |> to({user.display_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Welcome to SecureSharing!")
    |> text_body(welcome_text(user))
    |> html_body(welcome_html(user))
  end

  @doc """
  Create a security alert email when password is changed.
  """
  def password_changed_email(user, metadata \\ %{}) do
    new()
    |> to({user.display_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Your SecureSharing password was changed")
    |> text_body(password_changed_text(user, metadata))
    |> html_body(password_changed_html(user, metadata))
  end

  @doc """
  Create a forgot password email that guides user to recovery options.

  Note: SecureSharing uses zero-knowledge encryption, so traditional password
  reset is not possible. This email explains the options available.
  """
  def forgot_password_email(user, recovery_available?) do
    new()
    |> to({user.display_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("SecureSharing Account Recovery Options")
    |> text_body(forgot_password_text(user, recovery_available?))
    |> html_body(forgot_password_html(user, recovery_available?))
  end

  # ============================================================================
  # Security Alert Emails
  # ============================================================================

  @doc """
  Create a security alert email when a new device logs in.
  """
  def new_device_login_email(user, device_info, login_metadata) do
    new()
    |> to({user.display_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("New device login to your SecureSharing account")
    |> text_body(new_device_login_text(user, device_info, login_metadata))
    |> html_body(new_device_login_html(user, device_info, login_metadata))
  end

  # ============================================================================
  # Sharing & Collaboration Emails
  # ============================================================================

  @doc """
  Create an invitation email for when a user is invited to join a tenant.
  """
  def invitation_email(invitee, tenant, inviter) do
    new()
    |> to({invitee.display_name || invitee.email, invitee.email})
    |> from({@from_name, @from_email})
    |> subject("You've been invited to join #{tenant.name} on SecureSharing")
    |> text_body(invitation_text(invitee, tenant, inviter))
    |> html_body(invitation_html(invitee, tenant, inviter))
  end

  @doc """
  Create an invitation email for a NEW user (invitation-only registration).

  This email is sent when an admin invites a new user who doesn't have an account yet.
  It includes a unique invitation link to register.
  """
  def new_user_invitation_email(invitation, invite_url) do
    tenant_name = invitation.tenant.name
    inviter_name = invitation.inviter.display_name || invitation.inviter.email

    new()
    |> to(invitation.email)
    |> from({@from_name, @from_email})
    |> subject("You've been invited to join #{tenant_name} on SecureSharing")
    |> text_body(new_user_invitation_text(invitation, invite_url, tenant_name, inviter_name))
    |> html_body(new_user_invitation_html(invitation, invite_url, tenant_name, inviter_name))
  end

  @doc """
  Create a notification email when an invitation is accepted.

  Sent to the inviter to let them know their invitation was accepted.
  """
  def invitation_accepted_email(inviter, new_user, tenant) do
    new()
    |> to({inviter.display_name || inviter.email, inviter.email})
    |> from({@from_name, @from_email})
    |> subject("#{new_user.display_name || new_user.email} accepted your invitation")
    |> text_body(invitation_accepted_text(inviter, new_user, tenant))
    |> html_body(invitation_accepted_html(inviter, new_user, tenant))
  end

  @doc """
  Create a welcome email with tenant info (for invitation-based registration).
  """
  def welcome_email(user, tenant) do
    new()
    |> to({user.display_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Welcome to #{tenant.name} on SecureSharing!")
    |> text_body(welcome_with_tenant_text(user, tenant))
    |> html_body(welcome_with_tenant_html(user, tenant))
  end

  @doc """
  Create a share notification email for when someone shares a file/folder.
  """
  def share_notification_email(recipient, grantor, resource_type, resource_name) do
    new()
    |> to({recipient.display_name || recipient.email, recipient.email})
    |> from({@from_name, @from_email})
    |> subject("#{grantor.display_name || grantor.email} shared a #{resource_type} with you")
    |> text_body(share_notification_text(recipient, grantor, resource_type, resource_name))
    |> html_body(share_notification_html(recipient, grantor, resource_type, resource_name))
  end

  @doc """
  Create a share expiry warning email.
  """
  def share_expiry_warning_email(recipient, grantor, resource_type, resource_name, expires_at) do
    new()
    |> to({recipient.display_name || recipient.email, recipient.email})
    |> from({@from_name, @from_email})
    |> subject("Shared #{resource_type} access expiring soon")
    |> text_body(
      share_expiry_warning_text(recipient, grantor, resource_type, resource_name, expires_at)
    )
    |> html_body(
      share_expiry_warning_html(recipient, grantor, resource_type, resource_name, expires_at)
    )
  end

  # ============================================================================
  # Recovery Emails
  # ============================================================================

  @doc """
  Create a recovery request notification email for trustees.
  """
  def recovery_request_email(trustee, requester) do
    new()
    |> to({trustee.display_name || trustee.email, trustee.email})
    |> from({@from_name, @from_email})
    |> subject("Recovery request from #{requester.display_name || requester.email}")
    |> text_body(recovery_request_text(trustee, requester))
    |> html_body(recovery_request_html(trustee, requester))
  end

  @doc """
  Create a recovery complete notification email.
  """
  def recovery_complete_email(user) do
    new()
    |> to({user.display_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Your SecureSharing account recovery is complete")
    |> text_body(recovery_complete_text(user))
    |> html_body(recovery_complete_html(user))
  end

  # ==================== Text Templates ====================

  # Account & Authentication

  defp verification_text(user, verification_url) do
    """
    Hi #{user.display_name || "there"},

    Thank you for signing up for SecureSharing!

    Please verify your email address by clicking the link below:

    #{verification_url}

    This link will expire in 24 hours.

    If you didn't create a SecureSharing account, you can safely ignore this email.

    Best regards,
    The SecureSharing Team
    """
  end

  defp welcome_text(user) do
    """
    Hi #{user.display_name || "there"},

    Welcome to SecureSharing!

    Your email has been verified and your account is now active. You're all set to start sharing files securely.

    SecureSharing uses end-to-end encryption, which means:
    - Your files are encrypted before they leave your device
    - Only you and people you share with can access your files
    - Even we cannot see your file contents

    Important: Your password is the key to your encryption. If you forget it, you'll need to use your trusted contacts to recover your account. We recommend setting up recovery in Settings > Recovery Setup.

    Get started:
    1. Download the app on your devices
    2. Set up trusted contacts for account recovery
    3. Start uploading and sharing files securely

    Best regards,
    The SecureSharing Team
    """
  end

  defp password_changed_text(user, metadata) do
    time = Map.get(metadata, :changed_at, DateTime.utc_now()) |> format_datetime()
    ip = Map.get(metadata, :ip_address, "Unknown")
    device = Map.get(metadata, :device, "Unknown device")

    """
    Hi #{user.display_name || "there"},

    Your SecureSharing password was changed.

    When: #{time}
    Device: #{device}
    IP Address: #{ip}

    If you made this change, no further action is needed.

    If you did NOT make this change, your account may be compromised. Please:
    1. Try to log in immediately and change your password
    2. Review your connected devices in Settings > Devices
    3. Contact support if you cannot access your account

    Best regards,
    The SecureSharing Team
    """
  end

  defp forgot_password_text(user, recovery_available?) do
    recovery_section =
      if recovery_available? do
        """
        OPTION 1: Use Account Recovery (Recommended)
        You have recovery set up with trusted contacts. Open the SecureSharing app and tap "Forgot Password" > "Use Recovery". Your trusted contacts will be notified to help you regain access.
        """
      else
        """
        OPTION 1: Set Up Recovery First
        You don't have recovery configured. Unfortunately, without recovery contacts, there's no way to recover your encrypted data if you've forgotten your password.
        """
      end

    """
    Hi #{user.display_name || "there"},

    We received a request to help you access your SecureSharing account.

    IMPORTANT: SecureSharing uses zero-knowledge encryption. This means we cannot reset your password because we don't have access to your encryption keys. Your password IS your key.

    #{recovery_section}

    OPTION 2: Create a New Account
    If recovery is not available, you can create a new account with the same email. However, this means:
    - All your previously encrypted files will be inaccessible
    - You'll start fresh with no files or shares

    Why can't you just reset my password?
    Traditional password reset would require us to have access to your encryption keys, which would defeat the purpose of end-to-end encryption. Your security is our priority.

    Best regards,
    The SecureSharing Team
    """
  end

  # Security Alerts

  defp new_device_login_text(user, device_info, login_metadata) do
    time = Map.get(login_metadata, :login_at, DateTime.utc_now()) |> format_datetime()
    ip = Map.get(login_metadata, :ip_address, "Unknown")
    location = Map.get(login_metadata, :location, "Unknown location")
    device_name = Map.get(device_info, :name, "Unknown device")
    device_platform = Map.get(device_info, :platform, "Unknown")

    """
    Hi #{user.display_name || "there"},

    A new device just logged into your SecureSharing account.

    Device: #{device_name}
    Platform: #{device_platform}
    Time: #{time}
    Location: #{location}
    IP Address: #{ip}

    If this was you, no action is needed.

    If this wasn't you:
    1. Go to Settings > Devices and remove the unknown device
    2. Change your password immediately
    3. Review your recent activity

    Best regards,
    The SecureSharing Team
    """
  end

  # Sharing

  defp invitation_text(invitee, tenant, inviter) do
    """
    Hi #{invitee.display_name || "there"},

    #{inviter.display_name || inviter.email} has invited you to join #{tenant.name} on SecureSharing.

    SecureSharing is a secure file sharing platform with end-to-end encryption. Your files are encrypted before they leave your device, ensuring only you and people you share with can access them.

    To accept this invitation, open the SecureSharing app and go to Settings > Organization Invitations.

    If you haven't installed the app yet, you can download it from:
    - Android: [Play Store Link]
    - iOS: [App Store Link]

    Best regards,
    The SecureSharing Team
    """
  end

  defp new_user_invitation_text(invitation, invite_url, tenant_name, inviter_name) do
    message_section =
      if invitation.message do
        """

        Personal message from #{inviter_name}:
        "#{invitation.message}"
        """
      else
        ""
      end

    expiry_date = format_datetime(invitation.expires_at)

    """
    Hi there,

    #{inviter_name} has invited you to join #{tenant_name} on SecureSharing.
    #{message_section}

    SecureSharing is a secure file sharing platform with post-quantum encryption to protect your sensitive files. Your data is encrypted before it leaves your device, ensuring only you and people you share with can access it.

    To accept this invitation and create your account, click the link below:

    #{invite_url}

    This invitation expires on #{expiry_date}.

    What happens when you accept:
    1. You'll create a secure account with a password
    2. Your encryption keys will be generated on your device
    3. You'll immediately have access to #{tenant_name}

    If you weren't expecting this invitation, you can safely ignore this email.

    Best regards,
    The SecureSharing Team
    """
  end

  defp invitation_accepted_text(inviter, new_user, tenant) do
    """
    Hi #{inviter.display_name || "there"},

    Good news! #{new_user.display_name || new_user.email} has accepted your invitation to join #{tenant.name}.

    They are now a member of your organization and can start collaborating securely.

    Best regards,
    The SecureSharing Team
    """
  end

  defp welcome_with_tenant_text(user, tenant) do
    """
    Hi #{user.display_name || "there"},

    Welcome to #{tenant.name} on SecureSharing!

    Your account has been created and you're all set to start sharing files securely.

    SecureSharing uses end-to-end encryption, which means:
    - Your files are encrypted before they leave your device
    - Only you and people you share with can access your files
    - Even we cannot see your file contents

    Important: Your password is the key to your encryption. If you forget it, you'll need to use your trusted contacts to recover your account. We recommend setting up recovery in Settings > Recovery Setup.

    Get started:
    1. Download the app on your devices
    2. Set up trusted contacts for account recovery
    3. Start uploading and sharing files securely

    Best regards,
    The SecureSharing Team
    """
  end

  defp share_notification_text(recipient, grantor, resource_type, resource_name) do
    """
    Hi #{recipient.display_name || "there"},

    #{grantor.display_name || grantor.email} has shared a #{resource_type} with you: #{resource_name}

    Open the SecureSharing app to view and access this shared #{resource_type}.

    Best regards,
    The SecureSharing Team
    """
  end

  defp share_expiry_warning_text(recipient, grantor, resource_type, resource_name, expires_at) do
    expiry_time = format_datetime(expires_at)

    """
    Hi #{recipient.display_name || "there"},

    A #{resource_type} shared with you is expiring soon.

    #{resource_type |> String.capitalize()}: #{resource_name}
    Shared by: #{grantor.display_name || grantor.email}
    Expires: #{expiry_time}

    After this time, you will no longer have access to this #{resource_type}. If you need continued access, please contact #{grantor.display_name || grantor.email} to extend or renew the share.

    Best regards,
    The SecureSharing Team
    """
  end

  # Recovery

  defp recovery_request_text(trustee, requester) do
    """
    Hi #{trustee.display_name || "there"},

    #{requester.display_name || requester.email} has requested to recover their account and needs your help as a trusted contact.

    Please open the SecureSharing app and go to Settings > Recovery Dashboard to review and approve this request.

    If you did not expect this request, please contact the person directly to verify their identity before approving.

    Best regards,
    The SecureSharing Team
    """
  end

  defp recovery_complete_text(user) do
    """
    Hi #{user.display_name || "there"},

    Great news! Your SecureSharing account recovery is complete.

    Your trusted contacts have approved your recovery request, and your account access has been restored.

    What to do now:
    1. Log in to the SecureSharing app with your new password
    2. Verify that your files and folders are accessible
    3. Consider updating your trusted contacts if needed

    Security recommendation: If you suspect your previous password was compromised, please review your connected devices in Settings > Devices and remove any you don't recognize.

    Best regards,
    The SecureSharing Team
    """
  end

  # ==================== HTML Templates ====================

  @base_styles """
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
  .header { background: #4F46E5; color: white; padding: 20px; border-radius: 8px 8px 0 0; text-align: center; }
  .header-warning { background: #DC2626; }
  .header-success { background: #059669; }
  .header-info { background: #0284C7; }
  .content { background: #f9fafb; padding: 20px; border-radius: 0 0 8px 8px; }
  .button { display: inline-block; background: #4F46E5; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 20px 0; }
  .info-box { background: white; padding: 15px; border-radius: 6px; border: 1px solid #e5e7eb; margin: 15px 0; }
  .warning-box { background: #FEF2F2; border: 1px solid #FECACA; padding: 15px; border-radius: 6px; margin: 15px 0; }
  .success-box { background: #ECFDF5; border: 1px solid #A7F3D0; padding: 15px; border-radius: 6px; margin: 15px 0; }
  .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
  .detail-row { display: flex; padding: 8px 0; border-bottom: 1px solid #e5e7eb; }
  .detail-label { font-weight: 600; min-width: 120px; }
  ul { padding-left: 20px; }
  li { margin: 8px 0; }
  """

  # Account & Authentication HTML

  defp verification_html(user, verification_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header">
        <h1>Verify Your Email</h1>
      </div>
      <div class="content">
        <p>Hi #{user.display_name || "there"},</p>
        <p>Thank you for signing up for SecureSharing!</p>
        <p>Please verify your email address by clicking the button below:</p>
        <p style="text-align: center;">
          <a href="#{verification_url}" class="button">Verify Email Address</a>
        </p>
        <p style="font-size: 12px; color: #666;">Or copy and paste this link: #{verification_url}</p>
        <p>This link will expire in 24 hours.</p>
        <p style="font-size: 12px; color: #666;">If you didn't create a SecureSharing account, you can safely ignore this email.</p>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp welcome_html(user) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-success">
        <h1>Welcome to SecureSharing!</h1>
      </div>
      <div class="content">
        <p>Hi #{user.display_name || "there"},</p>
        <p>Your email has been verified and your account is now active. You're all set to start sharing files securely.</p>

        <div class="info-box">
          <strong>SecureSharing uses end-to-end encryption:</strong>
          <ul>
            <li>Your files are encrypted before they leave your device</li>
            <li>Only you and people you share with can access your files</li>
            <li>Even we cannot see your file contents</li>
          </ul>
        </div>

        <div class="warning-box">
          <strong>Important:</strong> Your password is the key to your encryption. If you forget it, you'll need to use your trusted contacts to recover your account. We recommend setting up recovery in <strong>Settings > Recovery Setup</strong>.
        </div>

        <p><strong>Get started:</strong></p>
        <ol>
          <li>Download the app on your devices</li>
          <li>Set up trusted contacts for account recovery</li>
          <li>Start uploading and sharing files securely</li>
        </ol>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp password_changed_html(user, metadata) do
    time = Map.get(metadata, :changed_at, DateTime.utc_now()) |> format_datetime()
    ip = Map.get(metadata, :ip_address, "Unknown")
    device = Map.get(metadata, :device, "Unknown device")

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-warning">
        <h1>Password Changed</h1>
      </div>
      <div class="content">
        <p>Hi #{user.display_name || "there"},</p>
        <p>Your SecureSharing password was changed.</p>

        <div class="info-box">
          <div class="detail-row"><span class="detail-label">When:</span> #{time}</div>
          <div class="detail-row"><span class="detail-label">Device:</span> #{device}</div>
          <div class="detail-row"><span class="detail-label">IP Address:</span> #{ip}</div>
        </div>

        <p>If you made this change, no further action is needed.</p>

        <div class="warning-box">
          <strong>If you did NOT make this change</strong>, your account may be compromised. Please:
          <ol>
            <li>Try to log in immediately and change your password</li>
            <li>Review your connected devices in Settings > Devices</li>
            <li>Contact support if you cannot access your account</li>
          </ol>
        </div>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp forgot_password_html(user, recovery_available?) do
    recovery_section =
      if recovery_available? do
        """
        <div class="success-box">
          <strong>OPTION 1: Use Account Recovery (Recommended)</strong>
          <p>You have recovery set up with trusted contacts. Open the SecureSharing app and tap <strong>"Forgot Password" > "Use Recovery"</strong>. Your trusted contacts will be notified to help you regain access.</p>
        </div>
        """
      else
        """
        <div class="warning-box">
          <strong>OPTION 1: Set Up Recovery First</strong>
          <p>You don't have recovery configured. Unfortunately, without recovery contacts, there's no way to recover your encrypted data if you've forgotten your password.</p>
        </div>
        """
      end

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-info">
        <h1>Account Recovery Options</h1>
      </div>
      <div class="content">
        <p>Hi #{user.display_name || "there"},</p>
        <p>We received a request to help you access your SecureSharing account.</p>

        <div class="warning-box">
          <strong>IMPORTANT:</strong> SecureSharing uses zero-knowledge encryption. This means we cannot reset your password because we don't have access to your encryption keys. <strong>Your password IS your key.</strong>
        </div>

        #{recovery_section}

        <div class="info-box">
          <strong>OPTION 2: Create a New Account</strong>
          <p>If recovery is not available, you can create a new account with the same email. However, this means:</p>
          <ul>
            <li>All your previously encrypted files will be inaccessible</li>
            <li>You'll start fresh with no files or shares</li>
          </ul>
        </div>

        <div class="info-box">
          <strong>Why can't you just reset my password?</strong>
          <p>Traditional password reset would require us to have access to your encryption keys, which would defeat the purpose of end-to-end encryption. Your security is our priority.</p>
        </div>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  # Security Alerts HTML

  defp new_device_login_html(user, device_info, login_metadata) do
    time = Map.get(login_metadata, :login_at, DateTime.utc_now()) |> format_datetime()
    ip = Map.get(login_metadata, :ip_address, "Unknown")
    location = Map.get(login_metadata, :location, "Unknown location")
    device_name = Map.get(device_info, :name, "Unknown device")
    device_platform = Map.get(device_info, :platform, "Unknown")

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-info">
        <h1>New Device Login</h1>
      </div>
      <div class="content">
        <p>Hi #{user.display_name || "there"},</p>
        <p>A new device just logged into your SecureSharing account.</p>

        <div class="info-box">
          <div class="detail-row"><span class="detail-label">Device:</span> #{device_name}</div>
          <div class="detail-row"><span class="detail-label">Platform:</span> #{device_platform}</div>
          <div class="detail-row"><span class="detail-label">Time:</span> #{time}</div>
          <div class="detail-row"><span class="detail-label">Location:</span> #{location}</div>
          <div class="detail-row"><span class="detail-label">IP Address:</span> #{ip}</div>
        </div>

        <p>If this was you, no action is needed.</p>

        <div class="warning-box">
          <strong>If this wasn't you:</strong>
          <ol>
            <li>Go to <strong>Settings > Devices</strong> and remove the unknown device</li>
            <li>Change your password immediately</li>
            <li>Review your recent activity</li>
          </ol>
        </div>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  # Sharing HTML

  defp invitation_html(invitee, tenant, inviter) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #4F46E5; color: white; padding: 20px; border-radius: 8px 8px 0 0; text-align: center; }
        .content { background: #f9fafb; padding: 20px; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #4F46E5; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 20px 0; }
        .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>You're Invited!</h1>
      </div>
      <div class="content">
        <p>Hi #{invitee.display_name || "there"},</p>
        <p><strong>#{inviter.display_name || inviter.email}</strong> has invited you to join <strong>#{tenant.name}</strong> on SecureSharing.</p>
        <p>SecureSharing is a secure file sharing platform with end-to-end encryption. Your files are encrypted before they leave your device, ensuring only you and people you share with can access them.</p>
        <p>To accept this invitation, open the SecureSharing app and go to <strong>Settings > Organization Invitations</strong>.</p>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp share_notification_html(recipient, grantor, resource_type, resource_name) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: #4F46E5; color: white; padding: 20px; border-radius: 8px 8px 0 0; text-align: center; }
        .content { background: #f9fafb; padding: 20px; border-radius: 0 0 8px 8px; }
        .resource { background: white; padding: 15px; border-radius: 6px; border: 1px solid #e5e7eb; margin: 15px 0; }
        .footer { margin-top: 20px; font-size: 12px; color: #666; text-align: center; }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>New Share</h1>
      </div>
      <div class="content">
        <p>Hi #{recipient.display_name || "there"},</p>
        <p><strong>#{grantor.display_name || grantor.email}</strong> has shared a #{resource_type} with you:</p>
        <div class="resource">
          <strong>#{resource_name}</strong>
        </div>
        <p>Open the SecureSharing app to view and access this shared #{resource_type}.</p>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp share_expiry_warning_html(recipient, grantor, resource_type, resource_name, expires_at) do
    expiry_time = format_datetime(expires_at)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-info">
        <h1>Share Expiring Soon</h1>
      </div>
      <div class="content">
        <p>Hi #{recipient.display_name || "there"},</p>
        <p>A #{resource_type} shared with you is expiring soon.</p>

        <div class="info-box">
          <div class="detail-row"><span class="detail-label">#{resource_type |> String.capitalize()}:</span> #{resource_name}</div>
          <div class="detail-row"><span class="detail-label">Shared by:</span> #{grantor.display_name || grantor.email}</div>
          <div class="detail-row"><span class="detail-label">Expires:</span> #{expiry_time}</div>
        </div>

        <p>After this time, you will no longer have access to this #{resource_type}. If you need continued access, please contact <strong>#{grantor.display_name || grantor.email}</strong> to extend or renew the share.</p>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp new_user_invitation_html(invitation, invite_url, tenant_name, inviter_name) do
    message_section =
      if invitation.message do
        """
        <div class="info-box">
          <strong>Personal message from #{inviter_name}:</strong>
          <p style="font-style: italic;">"#{invitation.message}"</p>
        </div>
        """
      else
        ""
      end

    expiry_date = format_datetime(invitation.expires_at)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header">
        <h1>You're Invited!</h1>
      </div>
      <div class="content">
        <p>Hi there,</p>
        <p><strong>#{inviter_name}</strong> has invited you to join <strong>#{tenant_name}</strong> on SecureSharing.</p>

        #{message_section}

        <p>SecureSharing is a secure file sharing platform with <strong>post-quantum encryption</strong> to protect your sensitive files. Your data is encrypted before it leaves your device, ensuring only you and people you share with can access it.</p>

        <p style="text-align: center;">
          <a href="#{invite_url}" class="button">Accept Invitation</a>
        </p>
        <p style="font-size: 12px; color: #666; text-align: center;">Or copy and paste this link: #{invite_url}</p>

        <div class="info-box">
          <strong>What happens when you accept:</strong>
          <ol>
            <li>You'll create a secure account with a password</li>
            <li>Your encryption keys will be generated on your device</li>
            <li>You'll immediately have access to #{tenant_name}</li>
          </ol>
        </div>

        <p style="font-size: 12px; color: #666;">This invitation expires on #{expiry_date}.</p>
        <p style="font-size: 12px; color: #666;">If you weren't expecting this invitation, you can safely ignore this email.</p>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with post-quantum encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp invitation_accepted_html(inviter, new_user, tenant) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-success">
        <h1>Invitation Accepted!</h1>
      </div>
      <div class="content">
        <p>Hi #{inviter.display_name || "there"},</p>

        <div class="success-box">
          <strong>#{new_user.display_name || new_user.email}</strong> has accepted your invitation to join <strong>#{tenant.name}</strong>.
        </div>

        <p>They are now a member of your organization and can start collaborating securely.</p>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with post-quantum encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp welcome_with_tenant_html(user, tenant) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-success">
        <h1>Welcome to #{tenant.name}!</h1>
      </div>
      <div class="content">
        <p>Hi #{user.display_name || "there"},</p>
        <p>Your account has been created and you're all set to start sharing files securely.</p>

        <div class="info-box">
          <strong>SecureSharing uses end-to-end encryption:</strong>
          <ul>
            <li>Your files are encrypted before they leave your device</li>
            <li>Only you and people you share with can access your files</li>
            <li>Even we cannot see your file contents</li>
          </ul>
        </div>

        <div class="warning-box">
          <strong>Important:</strong> Your password is the key to your encryption. If you forget it, you'll need to use your trusted contacts to recover your account. We recommend setting up recovery in <strong>Settings > Recovery Setup</strong>.
        </div>

        <p><strong>Get started:</strong></p>
        <ol>
          <li>Download the app on your devices</li>
          <li>Set up trusted contacts for account recovery</li>
          <li>Start uploading and sharing files securely</li>
        </ol>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with post-quantum encryption</p>
      </div>
    </body>
    </html>
    """
  end

  # Recovery HTML

  defp recovery_request_html(trustee, requester) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-warning">
        <h1>Recovery Request</h1>
      </div>
      <div class="content">
        <p>Hi #{trustee.display_name || "there"},</p>
        <p><strong>#{requester.display_name || requester.email}</strong> has requested to recover their account and needs your help as a trusted contact.</p>
        <p>Please open the SecureSharing app and go to <strong>Settings > Recovery Dashboard</strong> to review and approve this request.</p>
        <div class="warning-box">
          <strong>Security Notice:</strong> If you did not expect this request, please contact the person directly to verify their identity before approving.
        </div>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  defp recovery_complete_html(user) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>#{@base_styles}</style>
    </head>
    <body>
      <div class="header header-success">
        <h1>Recovery Complete!</h1>
      </div>
      <div class="content">
        <p>Hi #{user.display_name || "there"},</p>
        <p>Great news! Your SecureSharing account recovery is complete.</p>

        <div class="success-box">
          Your trusted contacts have approved your recovery request, and your account access has been restored.
        </div>

        <p><strong>What to do now:</strong></p>
        <ol>
          <li>Log in to the SecureSharing app with your new password</li>
          <li>Verify that your files and folders are accessible</li>
          <li>Consider updating your trusted contacts if needed</li>
        </ol>

        <div class="warning-box">
          <strong>Security recommendation:</strong> If you suspect your previous password was compromised, please review your connected devices in <strong>Settings > Devices</strong> and remove any you don't recognize.
        </div>
      </div>
      <div class="footer">
        <p>SecureSharing - Secure file sharing with end-to-end encryption</p>
      </div>
    </body>
    </html>
    """
  end

  # ==================== Helpers ====================

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y at %H:%M UTC")
  end

  defp format_datetime(_), do: "Unknown time"
end
