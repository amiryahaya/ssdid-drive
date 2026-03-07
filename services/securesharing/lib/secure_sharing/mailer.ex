defmodule SecureSharing.Mailer do
  @moduledoc """
  Email delivery configuration using Swoosh.

  Adapters can be configured per environment:
  - Development: Swoosh.Adapters.Local (for preview in browser)
  - Test: Swoosh.Adapters.Test
  - Production: Swoosh.Adapters.SMTP or cloud provider (SendGrid, Mailgun, etc.)
  """
  use Swoosh.Mailer, otp_app: :secure_sharing
end
