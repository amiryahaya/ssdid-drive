import { useState, useEffect } from 'react';
import { Plus, X, Loader2, AlertTriangle } from 'lucide-react';
import { useRecoveryStore, RecoverySetup } from '@/stores/recoveryStore';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/Button';
import { useToast } from '@/hooks/useToast';

interface RecoverySetupDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  existingSetup?: RecoverySetup | null;
  onComplete?: () => void;
}

export function RecoverySetupDialog({
  open,
  onOpenChange,
  existingSetup,
  onComplete,
}: RecoverySetupDialogProps) {
  const { setupRecovery, updateRecovery, isSettingUp, error, clearError } =
    useRecoveryStore();
  const { success, error: showError } = useToast();

  const [threshold, setThreshold] = useState(2);
  const [emails, setEmails] = useState<string[]>(['', '']);
  const [emailErrors, setEmailErrors] = useState<string[]>([]);

  // Reset form when dialog opens
  useEffect(() => {
    if (open) {
      if (existingSetup) {
        setThreshold(existingSetup.threshold);
        setEmails(existingSetup.trustees.map((t) => t.email));
      } else {
        setThreshold(2);
        setEmails(['', '']);
      }
      setEmailErrors([]);
      clearError();
    }
  }, [open, existingSetup, clearError]);

  const validateEmail = (email: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  };

  const handleAddEmail = () => {
    setEmails([...emails, '']);
    setEmailErrors([...emailErrors, '']);
  };

  const handleRemoveEmail = (index: number) => {
    if (emails.length <= 2) return; // Minimum 2 trustees
    setEmails(emails.filter((_, i) => i !== index));
    setEmailErrors(emailErrors.filter((_, i) => i !== index));
  };

  const handleEmailChange = (index: number, value: string) => {
    const newEmails = [...emails];
    newEmails[index] = value;
    setEmails(newEmails);

    // Clear error when user starts typing
    if (emailErrors[index]) {
      const newErrors = [...emailErrors];
      newErrors[index] = '';
      setEmailErrors(newErrors);
    }
  };

  const validateForm = (): boolean => {
    const newErrors: string[] = [];
    let isValid = true;

    // Validate each email
    emails.forEach((email, index) => {
      if (!email.trim()) {
        newErrors[index] = 'Email is required';
        isValid = false;
      } else if (!validateEmail(email)) {
        newErrors[index] = 'Invalid email format';
        isValid = false;
      } else if (emails.filter((e) => e.toLowerCase() === email.toLowerCase()).length > 1) {
        newErrors[index] = 'Duplicate email';
        isValid = false;
      } else {
        newErrors[index] = '';
      }
    });

    setEmailErrors(newErrors);

    // Validate threshold
    const validEmailCount = emails.filter((e) => e.trim() && validateEmail(e)).length;
    if (threshold > validEmailCount) {
      showError({
        title: 'Invalid threshold',
        description: `Threshold cannot be greater than the number of trustees (${validEmailCount})`,
      });
      isValid = false;
    }

    return isValid;
  };

  const handleSubmit = async () => {
    if (!validateForm()) return;

    const validEmails = emails.filter((e) => e.trim());

    try {
      if (existingSetup) {
        await updateRecovery(threshold, validEmails);
        success({
          title: 'Recovery updated',
          description: 'Your recovery configuration has been updated',
        });
      } else {
        await setupRecovery(threshold, validEmails);
        success({
          title: 'Recovery configured',
          description: 'Invitations have been sent to your trusted contacts',
        });
      }
      onOpenChange(false);
      onComplete?.();
    } catch (err) {
      showError({
        title: 'Setup failed',
        description: String(err),
      });
    }
  };

  const validEmailCount = emails.filter((e) => e.trim() && validateEmail(e)).length;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>
            {existingSetup ? 'Update Recovery Setup' : 'Set Up Account Recovery'}
          </DialogTitle>
          <DialogDescription>
            Choose trusted contacts who can help you recover your account if you
            lose access to your device.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Threshold Selection */}
          <div className="space-y-2">
            <label className="text-sm font-medium">
              Recovery Threshold
            </label>
            <div className="flex items-center gap-4">
              <select
                value={threshold}
                onChange={(e) => setThreshold(Number(e.target.value))}
                className="flex h-10 w-24 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                {[2, 3, 4, 5].map((n) => (
                  <option key={n} value={n} disabled={n > validEmailCount}>
                    {n}
                  </option>
                ))}
              </select>
              <span className="text-sm text-muted-foreground">
                of {validEmailCount || emails.length} trustees required for recovery
              </span>
            </div>
            <p className="text-xs text-muted-foreground">
              Minimum 2 trustees required for security
            </p>
          </div>

          {/* Trustee Emails */}
          <div className="space-y-2">
            <label className="text-sm font-medium">Trusted Contacts</label>
            <div className="space-y-2">
              {emails.map((email, index) => (
                <div key={index} className="flex items-center gap-2">
                  <div className="flex-1">
                    <input
                      type="email"
                      placeholder="trustee@example.com"
                      value={email}
                      onChange={(e) => handleEmailChange(index, e.target.value)}
                      className={`flex h-10 w-full rounded-md border bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${
                        emailErrors[index]
                          ? 'border-destructive'
                          : 'border-input'
                      }`}
                    />
                    {emailErrors[index] && (
                      <p className="text-xs text-destructive mt-1">
                        {emailErrors[index]}
                      </p>
                    )}
                  </div>
                  {emails.length > 2 && (
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      onClick={() => handleRemoveEmail(index)}
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              ))}
            </div>
            {emails.length < 5 && (
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={handleAddEmail}
                className="mt-2"
              >
                <Plus className="h-4 w-4 mr-2" />
                Add Trustee
              </Button>
            )}
          </div>

          {/* Warning */}
          <div className="flex items-start gap-2 p-3 rounded-lg bg-amber-500/10 text-amber-700 dark:text-amber-400 text-sm">
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
            <div>
              <p className="font-medium">Important</p>
              <p className="text-xs opacity-80">
                Only add people you trust completely. They will be able to help
                recover your account and access your encrypted files.
              </p>
            </div>
          </div>

          {error && (
            <div className="p-3 rounded-lg bg-destructive/10 text-destructive text-sm">
              {error}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={isSettingUp}>
            {isSettingUp && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
            {existingSetup ? 'Update' : 'Set Up Recovery'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
