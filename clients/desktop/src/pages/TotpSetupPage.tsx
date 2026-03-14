import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { QRCodeSVG } from 'qrcode.react';
import { Button } from '@/components/ui/Button';
import { OtpInput } from '@/components/auth/OtpInput';
import { tauriService } from '@/services/tauri';
import { Loader2, Shield, Copy, Check, AlertTriangle } from 'lucide-react';

type Step = 'loading' | 'qr' | 'confirm' | 'backup-codes' | 'error';

export function TotpSetupPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState<Step>('loading');
  const [otpauthUri, setOtpauthUri] = useState('');
  const [secret, setSecret] = useState('');
  const [backupCodes, setBackupCodes] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    (async () => {
      try {
        const result = await tauriService.totpSetup();
        setOtpauthUri(result.otpauth_uri);
        setSecret(result.secret);
        setStep('qr');
      } catch (e) {
        setError(e instanceof Error ? e.message : String(e));
        setStep('error');
      }
    })();
  }, []);

  const handleConfirm = async (code: string) => {
    setIsLoading(true);
    setError('');
    try {
      const result = await tauriService.totpSetupConfirm(code);
      setBackupCodes(result.backup_codes);
      setStep('backup-codes');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setIsLoading(false);
    }
  };

  const handleCopySecret = async () => {
    await navigator.clipboard.writeText(secret);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDone = () => {
    navigate('/files');
  };

  if (step === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (step === 'error') {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <AlertTriangle className="h-8 w-8 text-destructive mx-auto mb-4" />
          <p className="text-destructive mb-4">{error}</p>
          <Button onClick={() => navigate('/files')}>Go back</Button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Header */}
        <div className="flex flex-col items-center mb-6">
          <div className="h-16 w-16 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
            <Shield className="h-8 w-8 text-primary" />
          </div>
          <h1 className="text-2xl font-bold">
            {step === 'qr' && 'Set Up Authenticator'}
            {step === 'confirm' && 'Verify Setup'}
            {step === 'backup-codes' && 'Save Backup Codes'}
          </h1>
        </div>

        {/* QR Step */}
        {step === 'qr' && (
          <div className="space-y-6">
            <p className="text-sm text-muted-foreground text-center">
              Scan this QR code with your authenticator app (Google Authenticator, Authy, etc.)
            </p>
            <div className="bg-white p-4 rounded-xl shadow-inner flex justify-center">
              <QRCodeSVG value={otpauthUri} size={200} level="M" />
            </div>
            <div className="text-center">
              <p className="text-xs text-muted-foreground mb-1">Or enter this key manually:</p>
              <button
                onClick={handleCopySecret}
                className="inline-flex items-center gap-1 text-sm font-mono bg-muted px-3 py-1.5 rounded-lg hover:bg-muted/80"
              >
                {secret}
                {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
              </button>
            </div>
            <Button className="w-full" onClick={() => setStep('confirm')}>
              I've scanned the QR code
            </Button>
          </div>
        )}

        {/* Confirm Step */}
        {step === 'confirm' && (
          <div className="space-y-6">
            <p className="text-sm text-muted-foreground text-center">
              Enter the 6-digit code from your authenticator app to confirm setup
            </p>
            <OtpInput
              onComplete={handleConfirm}
              disabled={isLoading}
              error={error || undefined}
            />
            {isLoading && (
              <div className="flex justify-center">
                <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
              </div>
            )}
            <button
              onClick={() => { setStep('qr'); setError(''); }}
              className="text-sm text-muted-foreground hover:text-foreground mx-auto block"
            >
              Back to QR code
            </button>
          </div>
        )}

        {/* Backup Codes Step */}
        {step === 'backup-codes' && (
          <div className="space-y-6">
            <div className="p-4 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg">
              <div className="flex items-start gap-2">
                <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />
                <p className="text-sm text-amber-800 dark:text-amber-200">
                  Save these backup codes in a safe place. You can use each code once if you lose access to your authenticator app.
                </p>
              </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
              {backupCodes.map((code, i) => (
                <div key={i} className="font-mono text-sm bg-muted px-3 py-2 rounded-lg text-center">
                  {code}
                </div>
              ))}
            </div>
            <Button
              variant="outline"
              className="w-full"
              onClick={async () => {
                await navigator.clipboard.writeText(backupCodes.join('\n'));
                setCopied(true);
                setTimeout(() => setCopied(false), 2000);
              }}
            >
              {copied ? <Check className="h-4 w-4 mr-2" /> : <Copy className="h-4 w-4 mr-2" />}
              {copied ? 'Copied!' : 'Copy all codes'}
            </Button>
            <Button className="w-full" onClick={handleDone}>
              I've saved my backup codes
            </Button>
          </div>
        )}
      </div>
    </div>
  );
}
