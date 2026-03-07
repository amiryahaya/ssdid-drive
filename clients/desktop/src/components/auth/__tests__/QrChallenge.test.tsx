import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { QrChallenge } from '../QrChallenge';

// Mock createChallenge from tauri service
const mockCreateChallenge = vi.fn();
vi.mock('../../../services/tauri', () => ({
  createChallenge: (...args: unknown[]) => mockCreateChallenge(...args),
}));

// Mock qrcode.react
vi.mock('qrcode.react', () => ({
  QRCodeSVG: ({ value }: { value: string }) => (
    <div data-testid="qr-code" data-value={value}>
      QR Code
    </div>
  ),
}));

const mockQrPayload = JSON.stringify({
  server_url: 'https://example.com',
  challenge_id: 'challenge-123',
  action: 'authenticate',
});

const mockChallengeResult = {
  serverDid: 'did:example:server',
  challengeId: 'challenge-123',
  qrPayload: mockQrPayload,
};

// Capture EventSource instances for simulating SSE events
let mockEventSourceInstance: {
  addEventListener: ReturnType<typeof vi.fn>;
  close: ReturnType<typeof vi.fn>;
  onerror: ((event: Event) => void) | null;
};

class MockEventSource {
  addEventListener = vi.fn();
  close = vi.fn();
  onerror: ((event: Event) => void) | null = null;

  constructor(_url: string) {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    mockEventSourceInstance = this;
  }
}

describe('QrChallenge', () => {
  const mockOnAuthenticated = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    mockCreateChallenge.mockReset();
    // Install mock EventSource on window/global
    vi.stubGlobal('EventSource', MockEventSource);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('should render loading state initially', () => {
    // Keep createChallenge pending so the component stays in loading state
    mockCreateChallenge.mockReturnValue(new Promise(() => {}));

    render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    expect(screen.getByText('Generating secure challenge...')).toBeInTheDocument();
  });

  it('should display QR code after challenge is created', async () => {
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);

    render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    expect(screen.getByTestId('qr-code')).toHaveAttribute(
      'data-value',
      mockQrPayload
    );
    expect(screen.getByText('Scan with SSDID Wallet')).toBeInTheDocument();
    expect(screen.getByText(/scan this QR code to sign in/)).toBeInTheDocument();
  });

  it('should show register text when action is register', async () => {
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);

    render(
      <QrChallenge action="register" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    expect(screen.getByText(/scan this QR code to register/)).toBeInTheDocument();
  });

  it('should show error state on failure', async () => {
    mockCreateChallenge.mockRejectedValue(new Error('Network error'));

    render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByText('Network error')).toBeInTheDocument();
    });

    expect(screen.getByRole('button', { name: /try again/i })).toBeInTheDocument();
  });

  it('should show default error message for non-Error rejections', async () => {
    mockCreateChallenge.mockRejectedValue('something went wrong');

    render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByText('something went wrong')).toBeInTheDocument();
    });
  });

  it('should retry when Try Again is clicked', async () => {
    mockCreateChallenge.mockRejectedValueOnce(new Error('Temporary failure'));

    const { user } = render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByText('Temporary failure')).toBeInTheDocument();
    });

    // Now make it succeed on retry
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);
    await user.click(screen.getByRole('button', { name: /try again/i }));

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    expect(mockCreateChallenge).toHaveBeenCalledTimes(2);
  });

  it('should call onAuthenticated callback when session received via SSE', async () => {
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);

    render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    // Simulate the SSE 'authenticated' event
    const authenticatedHandler = mockEventSourceInstance.addEventListener.mock.calls.find(
      (call: unknown[]) => call[0] === 'authenticated'
    )?.[1] as (e: MessageEvent) => void;

    expect(authenticatedHandler).toBeDefined();

    authenticatedHandler(
      new MessageEvent('authenticated', {
        data: JSON.stringify({ session_token: 'session-abc-123' }),
      })
    );

    expect(mockOnAuthenticated).toHaveBeenCalledWith('session-abc-123');
  });

  it('should show expired state when SSE timeout event is received', async () => {
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);

    render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    // Simulate the SSE 'timeout' event
    const timeoutHandler = mockEventSourceInstance.addEventListener.mock.calls.find(
      (call: unknown[]) => call[0] === 'timeout'
    )?.[1] as () => void;

    expect(timeoutHandler).toBeDefined();
    timeoutHandler();

    await waitFor(() => {
      expect(screen.getByText('QR code expired')).toBeInTheDocument();
    });

    expect(
      screen.getByRole('button', { name: /refresh qr code/i })
    ).toBeInTheDocument();
  });

  it('should refresh after expiry when Refresh QR Code is clicked', async () => {
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);

    const { user } = render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    // Trigger timeout
    const timeoutHandler = mockEventSourceInstance.addEventListener.mock.calls.find(
      (call: unknown[]) => call[0] === 'timeout'
    )?.[1] as () => void;
    timeoutHandler();

    await waitFor(() => {
      expect(screen.getByText('QR code expired')).toBeInTheDocument();
    });

    // Click refresh
    await user.click(screen.getByRole('button', { name: /refresh qr code/i }));

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    expect(mockCreateChallenge).toHaveBeenCalledTimes(2);
  });

  it('should pass the correct action to createChallenge', async () => {
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);

    render(
      <QrChallenge action="register" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(mockCreateChallenge).toHaveBeenCalledWith('register');
    });
  });

  it('should close EventSource on unmount', async () => {
    mockCreateChallenge.mockResolvedValue(mockChallengeResult);

    const { unmount } = render(
      <QrChallenge action="authenticate" onAuthenticated={mockOnAuthenticated} />
    );

    await waitFor(() => {
      expect(screen.getByTestId('qr-code')).toBeInTheDocument();
    });

    unmount();

    expect(mockEventSourceInstance.close).toHaveBeenCalled();
  });
});
