import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { TotpSetupPage } from '../TotpSetupPage';
import { tauriService } from '@/services/tauri';

// Mock useNavigate
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// Mock tauriService
vi.mock('@/services/tauri', () => ({
  tauriService: {
    totpSetup: vi.fn(),
    totpSetupConfirm: vi.fn(),
  },
}));

// Mock QRCodeSVG
vi.mock('qrcode.react', () => ({
  QRCodeSVG: ({ value }: { value: string }) => <div data-testid="qr-code" data-value={value} />,
}));

// Mock OtpInput
vi.mock('@/components/auth/OtpInput', () => ({
  OtpInput: ({ onComplete, disabled, error }: any) => (
    <div data-testid="otp-input">
      <button data-testid="complete-otp" onClick={() => onComplete('123456')} disabled={disabled}>Complete</button>
      {error && <span>{error}</span>}
    </div>
  ),
}));

describe('TotpSetupPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should show loading spinner initially', () => {
    // Keep totpSetup pending so it stays in loading state
    vi.mocked(tauriService.totpSetup).mockReturnValue(new Promise(() => {}));

    render(<TotpSetupPage />);

    // The loading step renders a Loader2 spinner inside a centered div
    // Since lucide-react renders SVGs, we check for the animation class
    const container = document.querySelector('.animate-spin');
    expect(container).toBeInTheDocument();
  });

  it('should show QR code after setup loads', async () => {
    vi.mocked(tauriService.totpSetup).mockResolvedValue({
      otpauth_uri: 'otpauth://totp/SSDID:test@example.com?secret=ABCDEF',
      secret: 'ABCDEF',
    });

    render(<TotpSetupPage />);

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });
    expect(screen.getByTestId('qr-code')).toHaveAttribute(
      'data-value',
      'otpauth://totp/SSDID:test@example.com?secret=ABCDEF'
    );
    expect(screen.getByText('ABCDEF')).toBeInTheDocument();
    expect(screen.getByText('Set Up Authenticator')).toBeInTheDocument();
  });

  it('should show error step when setup fails', async () => {
    vi.mocked(tauriService.totpSetup).mockRejectedValue(new Error('TOTP setup failed'));

    render(<TotpSetupPage />);

    await waitFor(() => {
      expect(screen.getByText('TOTP setup failed')).toBeInTheDocument();
    });
    expect(screen.getByRole('button', { name: 'Go back' })).toBeInTheDocument();
  });

  it('should navigate to /files when "Go back" is clicked on error step', async () => {
    vi.mocked(tauriService.totpSetup).mockRejectedValue(new Error('Setup error'));

    const { user } = render(<TotpSetupPage />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Go back' })).toBeInTheDocument();
    });

    await user.click(screen.getByRole('button', { name: 'Go back' }));

    expect(mockNavigate).toHaveBeenCalledWith('/files');
  });

  it('should show confirm step when "I\'ve scanned the QR code" is clicked', async () => {
    vi.mocked(tauriService.totpSetup).mockResolvedValue({
      otpauth_uri: 'otpauth://totp/test',
      secret: 'SECRET',
    });

    const { user } = render(<TotpSetupPage />);

    await waitFor(() => {
      expect(screen.getByText("I've scanned the QR code")).toBeInTheDocument();
    });

    await user.click(screen.getByText("I've scanned the QR code"));

    expect(screen.getByTestId('otp-input')).toBeInTheDocument();
    expect(screen.getByText('Verify Setup')).toBeInTheDocument();
  });

  it('should call totpSetupConfirm on confirm step', async () => {
    vi.mocked(tauriService.totpSetup).mockResolvedValue({
      otpauth_uri: 'otpauth://totp/test',
      secret: 'SECRET',
    });
    vi.mocked(tauriService.totpSetupConfirm).mockResolvedValue({
      backup_codes: ['code1', 'code2'],
    });

    const { user } = render(<TotpSetupPage />);

    // Wait for QR step
    await waitFor(() => {
      expect(screen.getByText("I've scanned the QR code")).toBeInTheDocument();
    });

    // Move to confirm step
    await user.click(screen.getByText("I've scanned the QR code"));

    // Complete OTP
    await user.click(screen.getByTestId('complete-otp'));

    await waitFor(() => {
      expect(tauriService.totpSetupConfirm).toHaveBeenCalledWith('123456');
    });
  });

  it('should show backup codes after confirm', async () => {
    vi.mocked(tauriService.totpSetup).mockResolvedValue({
      otpauth_uri: 'otpauth://totp/test',
      secret: 'SECRET',
    });
    vi.mocked(tauriService.totpSetupConfirm).mockResolvedValue({
      backup_codes: ['abc-123', 'def-456', 'ghi-789'],
    });

    const { user } = render(<TotpSetupPage />);

    // Wait for QR step
    await waitFor(() => {
      expect(screen.getByText("I've scanned the QR code")).toBeInTheDocument();
    });

    // Move to confirm step
    await user.click(screen.getByText("I've scanned the QR code"));

    // Complete OTP
    await user.click(screen.getByTestId('complete-otp'));

    // Wait for backup codes step
    await waitFor(() => {
      expect(screen.getByText('Save Backup Codes')).toBeInTheDocument();
    });
    expect(screen.getByText('abc-123')).toBeInTheDocument();
    expect(screen.getByText('def-456')).toBeInTheDocument();
    expect(screen.getByText('ghi-789')).toBeInTheDocument();
  });

  it('should navigate to /files when "I\'ve saved my backup codes" is clicked', async () => {
    vi.mocked(tauriService.totpSetup).mockResolvedValue({
      otpauth_uri: 'otpauth://totp/test',
      secret: 'SECRET',
    });
    vi.mocked(tauriService.totpSetupConfirm).mockResolvedValue({
      backup_codes: ['code1', 'code2'],
    });

    const { user } = render(<TotpSetupPage />);

    // Wait for QR step
    await waitFor(() => {
      expect(screen.getByText("I've scanned the QR code")).toBeInTheDocument();
    });

    // Move to confirm step
    await user.click(screen.getByText("I've scanned the QR code"));

    // Complete OTP
    await user.click(screen.getByTestId('complete-otp'));

    // Wait for backup codes step
    await waitFor(() => {
      expect(screen.getByText("I've saved my backup codes")).toBeInTheDocument();
    });

    await user.click(screen.getByText("I've saved my backup codes"));

    expect(mockNavigate).toHaveBeenCalledWith('/files');
  });
});
