import { useState, useEffect, useCallback, useRef } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { Loader2, RefreshCw, AlertCircle, Smartphone } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { createChallenge } from '@/services/tauri';

interface QrChallengeProps {
  action: 'authenticate' | 'register';
  onAuthenticated: (sessionToken: string) => void;
}

type ChallengeState = 'loading' | 'ready' | 'expired' | 'error';

export function QrChallenge({ action, onAuthenticated }: QrChallengeProps) {
  const [state, setState] = useState<ChallengeState>('loading');
  const [qrPayload, setQrPayload] = useState<string>('');
  const [challengeId, setChallengeId] = useState<string>('');
  const [serverUrl, setServerUrl] = useState<string>('');
  const [subscriberSecret, setSubscriberSecret] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string>('');
  const eventSourceRef = useRef<EventSource | null>(null);

  const initChallenge = useCallback(async () => {
    setState('loading');
    setErrorMessage('');

    try {
      const result = await createChallenge(action);
      setQrPayload(result.qrPayload);
      setChallengeId(result.challengeId);
      setSubscriberSecret(result.subscriberSecret);

      // Extract server URL from the QR payload
      const payload = JSON.parse(result.qrPayload);
      setServerUrl(payload.server_url);

      setState('ready');
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setErrorMessage(message);
      setState('error');
    }
  }, [action]);

  // Subscribe to SSE events when challenge is ready
  useEffect(() => {
    if (state !== 'ready' || !challengeId || !serverUrl || !subscriberSecret) {
      return;
    }

    const sseUrl = `${serverUrl}/api/auth/ssdid/events?challenge_id=${challengeId}&subscriber_secret=${subscriberSecret}`;
    const eventSource = new EventSource(sseUrl);
    eventSourceRef.current = eventSource;

    eventSource.addEventListener('authenticated', (e: MessageEvent) => {
      try {
        const data = JSON.parse(e.data);
        onAuthenticated(data.session_token);
      } catch (err) {
        console.error('Failed to parse authenticated event:', err);
      }
    });

    eventSource.addEventListener('timeout', () => {
      setState('expired');
    });

    eventSource.onerror = () => {
      // SSE connection errors are expected when server is not yet available.
      // The QR remains scannable; the wallet will POST directly to the server
      // and the next reconnect will pick up the result.
      console.warn('SSE connection error for challenge', challengeId);
    };

    return () => {
      eventSource.close();
      eventSourceRef.current = null;
    };
  }, [state, challengeId, serverUrl, subscriberSecret, onAuthenticated]);

  // Initialize on mount
  useEffect(() => {
    initChallenge();
  }, [initChallenge]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      eventSourceRef.current?.close();
    };
  }, []);

  if (state === 'loading') {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground mb-4" />
        <p className="text-sm text-muted-foreground">Generating secure challenge...</p>
      </div>
    );
  }

  if (state === 'error') {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <AlertCircle className="h-8 w-8 text-destructive mb-4" />
        <p className="text-sm text-destructive mb-4">{errorMessage || 'Failed to create challenge'}</p>
        <Button variant="outline" onClick={initChallenge}>
          <RefreshCw className="h-4 w-4 mr-2" />
          Try Again
        </Button>
      </div>
    );
  }

  if (state === 'expired') {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <AlertCircle className="h-8 w-8 text-amber-500 mb-4" />
        <p className="text-sm text-muted-foreground mb-2">QR code expired</p>
        <p className="text-xs text-muted-foreground mb-4">Generate a new one to continue</p>
        <Button variant="outline" onClick={initChallenge}>
          <RefreshCw className="h-4 w-4 mr-2" />
          Refresh QR Code
        </Button>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center">
      {/* QR Code */}
      <div className="bg-white p-4 rounded-xl shadow-inner mb-6">
        <QRCodeSVG
          value={qrPayload}
          size={220}
          level="M"
          includeMargin={false}
        />
      </div>

      {/* Instructions */}
      <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
        <Smartphone className="h-4 w-4" />
        <span>Scan with SSDID Wallet</span>
      </div>
      <p className="text-xs text-muted-foreground text-center max-w-xs">
        Open your SSDID Wallet app and scan this QR code to{' '}
        {action === 'authenticate' ? 'sign in' : 'register'}
      </p>
    </div>
  );
}
