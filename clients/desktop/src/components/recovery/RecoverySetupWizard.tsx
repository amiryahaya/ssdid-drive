import { useState, useCallback, useEffect } from 'react';
import {
  Shield,
  ShieldCheck,
  Download,
  Loader2,
  AlertTriangle,
  CheckCircle2,
} from 'lucide-react';
import { save } from '@tauri-apps/plugin-dialog';
import { writeTextFile } from '@tauri-apps/plugin-fs';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/Button';
import { tauriService, SplitResult } from '@/services/tauri';
import { useToast } from '@/hooks/useToast';

// ==================== Types ====================

interface RecoverySetupWizardProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onComplete?: () => void;
}

type WizardStep = 'explanation' | 'download' | 'confirm';

// ==================== Step Indicator ====================

function StepIndicator({ current }: { current: WizardStep }) {
  const steps: WizardStep[] = ['explanation', 'download', 'confirm'];
  const labels = ['Overview', 'Save Shares', 'Done'];
  const currentIndex = steps.indexOf(current);

  return (
    <div className="flex items-center gap-2 mb-6">
      {steps.map((step, idx) => (
        <div key={step} className="flex items-center gap-2">
          <div
            className={`flex items-center justify-center w-7 h-7 rounded-full text-xs font-semibold transition-colors ${
              idx < currentIndex
                ? 'bg-primary text-primary-foreground'
                : idx === currentIndex
                ? 'bg-primary text-primary-foreground ring-2 ring-primary/30'
                : 'bg-muted text-muted-foreground'
            }`}
          >
            {idx < currentIndex ? (
              <CheckCircle2 className="h-4 w-4" />
            ) : (
              idx + 1
            )}
          </div>
          <span
            className={`text-xs ${
              idx === currentIndex
                ? 'text-foreground font-medium'
                : 'text-muted-foreground'
            }`}
          >
            {labels[idx]}
          </span>
          {idx < steps.length - 1 && (
            <div
              className={`flex-1 h-px w-8 ${
                idx < currentIndex ? 'bg-primary' : 'bg-border'
              }`}
            />
          )}
        </div>
      ))}
    </div>
  );
}

// ==================== Step 1: Explanation ====================

function ExplanationStep({ onNext }: { onNext: () => void }) {
  return (
    <>
      <DialogHeader>
        <div className="flex items-center gap-3 mb-1">
          <div className="p-2 rounded-lg bg-primary/10 text-primary">
            <Shield className="h-6 w-6" />
          </div>
          <DialogTitle className="text-xl">Protect Your Files Forever</DialogTitle>
        </div>
        <DialogDescription className="sr-only">
          Recovery setup overview
        </DialogDescription>
      </DialogHeader>

      <div className="space-y-4 py-2">
        <p className="text-sm text-foreground leading-relaxed">
          Your encryption keys exist <strong>only on this device</strong>. If you lose
          this device without a recovery setup, your files will be{' '}
          <strong>permanently inaccessible</strong> — no password reset, no support
          ticket can help.
        </p>

        <div className="rounded-lg border bg-muted/40 p-4 space-y-3">
          <h4 className="text-sm font-semibold">How recovery works</h4>
          <ul className="space-y-2 text-sm text-muted-foreground">
            <li className="flex items-start gap-2">
              <span className="mt-0.5 flex-shrink-0 w-5 h-5 rounded-full bg-primary/10 text-primary text-xs flex items-center justify-center font-semibold">
                1
              </span>
              Your master key is split into <strong>3 shares</strong> using
              Shamir's Secret Sharing.
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-0.5 flex-shrink-0 w-5 h-5 rounded-full bg-primary/10 text-primary text-xs flex items-center justify-center font-semibold">
                2
              </span>
              You download 2 shares — one for yourself, one to give to a trusted
              person or store offsite.
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-0.5 flex-shrink-0 w-5 h-5 rounded-full bg-primary/10 text-primary text-xs flex items-center justify-center font-semibold">
                3
              </span>
              The third share is stored securely on the server.
            </li>
            <li className="flex items-start gap-2">
              <span className="mt-0.5 flex-shrink-0 w-5 h-5 rounded-full bg-primary/10 text-primary text-xs flex items-center justify-center font-semibold">
                4
              </span>
              Any <strong>2 of 3 shares</strong> are enough to recover access on a
              new device.
            </li>
          </ul>
        </div>

        <div className="flex items-start gap-2 p-3 rounded-lg bg-amber-500/10 text-amber-700 dark:text-amber-400 text-sm">
          <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
          <p>
            Setup takes about <strong>2 minutes</strong>. Have a safe place ready to
            store your recovery files before continuing.
          </p>
        </div>
      </div>

      <DialogFooter>
        <Button onClick={onNext} className="w-full sm:w-auto">
          Begin Setup
        </Button>
      </DialogFooter>
    </>
  );
}

// ==================== Step 2: Generate & Download Shares ====================

interface DownloadStepProps {
  onNext: (shares: SplitResult) => void;
}

function DownloadStep({ onNext }: DownloadStepProps) {
  const { error: showError } = useToast();

  const [shares, setShares] = useState<SplitResult | null>(null);
  const [isGenerating, setIsGenerating] = useState(false);
  const [isSavingSelf, setIsSavingSelf] = useState(false);
  const [isSavingTrusted, setIsSavingTrusted] = useState(false);
  const [selfSaved, setSelfSaved] = useState(false);
  const [trustedSaved, setTrustedSaved] = useState(false);
  const [selfConfirmed, setSelfConfirmed] = useState(false);
  const [trustedConfirmed, setTrustedConfirmed] = useState(false);

  const generateShares = useCallback(async () => {
    setIsGenerating(true);
    try {
      const result = await tauriService.splitMasterKey();
      setShares(result);
    } catch (err) {
      showError({
        title: 'Failed to generate shares',
        description: String(err),
      });
    } finally {
      setIsGenerating(false);
    }
  }, [showError]);

  // Auto-generate on mount
  useEffect(() => {
    generateShares();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleDownloadSelf = async () => {
    if (!shares) return;
    setIsSavingSelf(true);
    try {
      const path = await save({
        defaultPath: 'recovery-self.recovery',
        filters: [{ name: 'Recovery File', extensions: ['recovery'] }],
      });
      if (path) {
        await writeTextFile(path, shares.file1);
        setSelfSaved(true);
      }
    } catch (err) {
      showError({
        title: 'Failed to save file',
        description: String(err),
      });
    } finally {
      setIsSavingSelf(false);
    }
  };

  const handleDownloadTrusted = async () => {
    if (!shares) return;
    setIsSavingTrusted(true);
    try {
      const path = await save({
        defaultPath: 'recovery-trusted.recovery',
        filters: [{ name: 'Recovery File', extensions: ['recovery'] }],
      });
      if (path) {
        await writeTextFile(path, shares.file2);
        setTrustedSaved(true);
      }
    } catch (err) {
      showError({
        title: 'Failed to save file',
        description: String(err),
      });
    } finally {
      setIsSavingTrusted(false);
    }
  };

  const canProceed = selfConfirmed && trustedConfirmed;

  return (
    <>
      <DialogHeader>
        <DialogTitle>Save Your Recovery Shares</DialogTitle>
        <DialogDescription>
          Download both files and store them safely before continuing.
        </DialogDescription>
      </DialogHeader>

      <div className="space-y-5 py-2">
        {isGenerating ? (
          <div className="flex flex-col items-center justify-center py-10 gap-3 text-muted-foreground">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <p className="text-sm">Generating your recovery shares…</p>
          </div>
        ) : !shares ? (
          <div className="flex flex-col items-center justify-center py-8 gap-3">
            <p className="text-sm text-muted-foreground">
              Share generation failed.
            </p>
            <Button variant="outline" onClick={generateShares}>
              Retry
            </Button>
          </div>
        ) : (
          <>
            {/* Share 1 — Self */}
            <div className="rounded-lg border p-4 space-y-3">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold">Share 1 — Your Copy</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Store in a password manager, encrypted USB drive, or another
                    safe offline location.
                  </p>
                </div>
                <Button
                  size="sm"
                  variant={selfSaved ? 'outline' : 'default'}
                  onClick={handleDownloadSelf}
                  disabled={isSavingSelf}
                  className="shrink-0"
                >
                  {isSavingSelf ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : selfSaved ? (
                    <>
                      <CheckCircle2 className="h-4 w-4 mr-1 text-green-500" />
                      Saved
                    </>
                  ) : (
                    <>
                      <Download className="h-4 w-4 mr-1" />
                      Download
                    </>
                  )}
                </Button>
              </div>
              <label className="flex items-center gap-2 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={selfConfirmed}
                  onChange={(e) => setSelfConfirmed(e.target.checked)}
                  disabled={!selfSaved}
                  className="h-4 w-4 rounded border-input accent-primary disabled:opacity-40 disabled:cursor-not-allowed"
                />
                <span
                  className={`text-xs ${
                    selfSaved ? 'text-foreground' : 'text-muted-foreground'
                  }`}
                >
                  I confirm I&apos;ve saved this file in a safe location
                </span>
              </label>
            </div>

            {/* Share 2 — Trusted Person */}
            <div className="rounded-lg border p-4 space-y-3">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold">
                    Share 2 — Trusted Person
                  </p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Send this to a trusted friend, family member, or store it in
                    a separate secure location (e.g. cloud storage, safety
                    deposit box).
                  </p>
                </div>
                <Button
                  size="sm"
                  variant={trustedSaved ? 'outline' : 'default'}
                  onClick={handleDownloadTrusted}
                  disabled={isSavingTrusted}
                  className="shrink-0"
                >
                  {isSavingTrusted ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : trustedSaved ? (
                    <>
                      <CheckCircle2 className="h-4 w-4 mr-1 text-green-500" />
                      Saved
                    </>
                  ) : (
                    <>
                      <Download className="h-4 w-4 mr-1" />
                      Download
                    </>
                  )}
                </Button>
              </div>
              <label className="flex items-center gap-2 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={trustedConfirmed}
                  onChange={(e) => setTrustedConfirmed(e.target.checked)}
                  disabled={!trustedSaved}
                  className="h-4 w-4 rounded border-input accent-primary disabled:opacity-40 disabled:cursor-not-allowed"
                />
                <span
                  className={`text-xs ${
                    trustedSaved ? 'text-foreground' : 'text-muted-foreground'
                  }`}
                >
                  I confirm I&apos;ve sent or given this file to someone I trust
                </span>
              </label>
            </div>

            {/* Warning */}
            <div className="flex items-start gap-2 p-3 rounded-lg bg-destructive/10 text-destructive text-xs">
              <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
              <p>
                <strong>Do NOT store these files on this device.</strong> If you
                lose this device, files stored here will be lost along with it.
              </p>
            </div>
          </>
        )}
      </div>

      <DialogFooter>
        <Button
          onClick={() => shares && onNext(shares)}
          disabled={!canProceed || !shares}
          className="w-full sm:w-auto"
        >
          Continue
        </Button>
      </DialogFooter>
    </>
  );
}

// ==================== Step 3: Server Upload & Confirmation ====================

interface ConfirmStepProps {
  shares: SplitResult;
  onDone: () => void;
}

function ConfirmStep({ shares, onDone }: ConfirmStepProps) {
  const { error: showError } = useToast();
  const [isUploading, setIsUploading] = useState(false);
  const [isComplete, setIsComplete] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  const uploadServerShare = useCallback(async () => {
    setIsUploading(true);
    setUploadError(null);
    try {
      await tauriService.setupRecovery(shares.server_share, shares.key_proof);
      setIsComplete(true);
    } catch (err) {
      const msg = String(err);
      setUploadError(msg);
      showError({
        title: 'Failed to upload server share',
        description: msg,
      });
    } finally {
      setIsUploading(false);
    }
  }, [shares.server_share, shares.key_proof, showError]);

  // Auto-upload on mount
  useEffect(() => {
    uploadServerShare();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <>
      <DialogHeader>
        <div className="flex items-center gap-3 mb-1">
          {isComplete ? (
            <div className="p-2 rounded-lg bg-green-500/10 text-green-500">
              <ShieldCheck className="h-6 w-6" />
            </div>
          ) : (
            <div className="p-2 rounded-lg bg-primary/10 text-primary">
              <Shield className="h-6 w-6" />
            </div>
          )}
          <DialogTitle className="text-xl">
            {isComplete ? 'Recovery Active' : 'Activating Recovery…'}
          </DialogTitle>
        </div>
        <DialogDescription className="sr-only">
          Server share upload status
        </DialogDescription>
      </DialogHeader>

      <div className="py-4">
        {isUploading && (
          <div className="flex flex-col items-center justify-center py-10 gap-3 text-muted-foreground">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <p className="text-sm">Uploading server share securely…</p>
          </div>
        )}

        {isComplete && (
          <div className="space-y-4">
            <div className="flex flex-col items-center justify-center py-6 gap-3">
              <CheckCircle2 className="h-12 w-12 text-green-500" />
            </div>
            <p className="text-sm text-foreground leading-relaxed text-center">
              Recovery is active. You can now recover your files from any new
              device using any <strong>2 of your 3 recovery shares</strong>.
            </p>
            <div className="rounded-lg border bg-muted/40 p-4 space-y-2">
              <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Your 3 shares
              </h4>
              <ul className="space-y-1.5 text-sm">
                <li className="flex items-center gap-2 text-green-600 dark:text-green-400">
                  <CheckCircle2 className="h-4 w-4 shrink-0" />
                  Share 1 — saved to your safe location
                </li>
                <li className="flex items-center gap-2 text-green-600 dark:text-green-400">
                  <CheckCircle2 className="h-4 w-4 shrink-0" />
                  Share 2 — given to your trusted person
                </li>
                <li className="flex items-center gap-2 text-green-600 dark:text-green-400">
                  <CheckCircle2 className="h-4 w-4 shrink-0" />
                  Share 3 — stored on the server
                </li>
              </ul>
            </div>
          </div>
        )}

        {uploadError && !isUploading && (
          <div className="space-y-4">
            <div className="p-3 rounded-lg bg-destructive/10 text-destructive text-sm">
              <p className="font-medium">Upload failed</p>
              <p className="text-xs mt-1 opacity-80">{uploadError}</p>
            </div>
            <Button
              variant="outline"
              onClick={uploadServerShare}
              className="w-full"
            >
              Retry
            </Button>
          </div>
        )}
      </div>

      <DialogFooter>
        <Button
          onClick={onDone}
          disabled={!isComplete}
          className="w-full sm:w-auto"
        >
          Done
        </Button>
      </DialogFooter>
    </>
  );
}

// ==================== Main Wizard ====================

export function RecoverySetupWizard({
  open,
  onOpenChange,
  onComplete,
}: RecoverySetupWizardProps) {
  const [step, setStep] = useState<WizardStep>('explanation');
  const [shares, setShares] = useState<SplitResult | null>(null);

  // Reset to first step when the dialog opens
  const handleOpenChange = (nextOpen: boolean) => {
    if (nextOpen) {
      setStep('explanation');
      setShares(null);
    }
    onOpenChange(nextOpen);
  };

  const handleExplanationNext = () => setStep('download');

  const handleDownloadNext = (result: SplitResult) => {
    setShares(result);
    setStep('confirm');
  };

  const handleDone = () => {
    onOpenChange(false);
    onComplete?.();
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <StepIndicator current={step} />

        {step === 'explanation' && (
          <ExplanationStep onNext={handleExplanationNext} />
        )}

        {step === 'download' && (
          <DownloadStep onNext={handleDownloadNext} />
        )}

        {step === 'confirm' && shares && (
          <ConfirmStep shares={shares} onDone={handleDone} />
        )}
      </DialogContent>
    </Dialog>
  );
}
