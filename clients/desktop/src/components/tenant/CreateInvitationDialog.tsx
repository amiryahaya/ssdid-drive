import { useState } from 'react';
import { Copy, Check, Loader2, Mail } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { useTenantStore, type TenantRole } from '@/stores/tenantStore';
import {
  useInvitationStore,
  type CreateInvitationResponse,
} from '@/stores/invitationStore';
import { useToast } from '@/hooks/useToast';

interface CreateInvitationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_MESSAGE_LENGTH = 500;

export function CreateInvitationDialog({
  open,
  onOpenChange,
}: CreateInvitationDialogProps) {
  const { canManageTenant } = useTenantStore();
  const { isCreating, createInvitation } = useInvitationStore();
  const { success, error: showError } = useToast();

  const [email, setEmail] = useState('');
  const [emailError, setEmailError] = useState<string | null>(null);
  const [role, setRole] = useState<TenantRole>('member');
  const [message, setMessage] = useState('');
  const [result, setResult] = useState<CreateInvitationResponse | null>(null);
  const [copied, setCopied] = useState(false);

  const resetForm = () => {
    setEmail('');
    setEmailError(null);
    setRole('member');
    setMessage('');
    setResult(null);
    setCopied(false);
  };

  const handleClose = (isOpen: boolean) => {
    if (!isOpen) {
      resetForm();
    }
    onOpenChange(isOpen);
  };

  const validateEmail = (value: string): boolean => {
    if (!value.trim()) {
      setEmailError(null);
      return true; // email is optional
    }
    if (!EMAIL_REGEX.test(value)) {
      setEmailError('Please enter a valid email address');
      return false;
    }
    setEmailError(null);
    return true;
  };

  const handleCreate = async () => {
    if (!validateEmail(email)) return;

    try {
      const response = await createInvitation({
        email: email.trim() || undefined,
        role,
        message: message.trim() || undefined,
      });
      setResult(response);
      success({
        title: 'Invitation created',
        description: `Invite code: ${response.short_code}`,
      });
    } catch (err) {
      showError({
        title: 'Failed to create invitation',
        description: err instanceof Error ? err.message : String(err),
      });
    }
  };

  const handleCopy = async () => {
    if (!result) return;
    try {
      await navigator.clipboard.writeText(result.short_code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback for environments without clipboard API
      showError({
        title: 'Copy failed',
        description: 'Could not copy to clipboard',
      });
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Create Invitation</DialogTitle>
          <DialogDescription>
            {result
              ? 'Share this invite code with the person you want to invite.'
              : 'Invite someone to join your organization.'}
          </DialogDescription>
        </DialogHeader>

        {result ? (
          /* Success state — show the short code */
          <div className="space-y-4">
            <div className="flex flex-col items-center py-6">
              <p className="text-sm text-muted-foreground mb-3">Invite Code</p>
              <div className="flex items-center gap-3">
                <span className="text-3xl font-mono font-bold tracking-widest select-all">
                  {result.short_code}
                </span>
                <Button
                  variant="outline"
                  size="icon"
                  onClick={handleCopy}
                  aria-label="Copy invite code"
                >
                  {copied ? (
                    <Check className="h-4 w-4 text-green-500" />
                  ) : (
                    <Copy className="h-4 w-4" />
                  )}
                </Button>
              </div>
              {result.email && (
                <p className="text-sm text-muted-foreground mt-3 flex items-center gap-1">
                  <Mail className="h-3.5 w-3.5" />
                  Sent to {result.email}
                </p>
              )}
            </div>

            <DialogFooter>
              <Button onClick={() => handleClose(false)}>Done</Button>
            </DialogFooter>
          </div>
        ) : (
          /* Creation form */
          <div className="space-y-4">
            {/* Email */}
            <div>
              <label
                htmlFor="invite-email"
                className="block text-sm font-medium mb-1.5"
              >
                Email <span className="text-muted-foreground">(optional)</span>
              </label>
              <input
                id="invite-email"
                type="email"
                value={email}
                onChange={(e) => {
                  setEmail(e.target.value);
                  if (emailError) validateEmail(e.target.value);
                }}
                onBlur={() => validateEmail(email)}
                placeholder="user@example.com"
                className="w-full px-3 py-2 rounded-md border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
              />
              {emailError && (
                <p className="text-sm text-destructive mt-1">{emailError}</p>
              )}
              <p className="text-xs text-muted-foreground mt-1">
                Leave empty to create an open invite code.
              </p>
            </div>

            {/* Role */}
            <div>
              <label className="block text-sm font-medium mb-1.5">Role</label>
              <Select
                value={role}
                onValueChange={(value) => setRole(value as TenantRole)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="member">Member</SelectItem>
                  {canManageTenant && (
                    <SelectItem value="admin">Admin</SelectItem>
                  )}
                </SelectContent>
              </Select>
            </div>

            {/* Message */}
            <div>
              <label
                htmlFor="invite-message"
                className="block text-sm font-medium mb-1.5"
              >
                Message{' '}
                <span className="text-muted-foreground">(optional)</span>
              </label>
              <textarea
                id="invite-message"
                value={message}
                onChange={(e) => {
                  if (e.target.value.length <= MAX_MESSAGE_LENGTH) {
                    setMessage(e.target.value);
                  }
                }}
                placeholder="Add a personal note..."
                rows={3}
                className="w-full px-3 py-2 rounded-md border bg-background text-sm resize-none focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
              />
              <p className="text-xs text-muted-foreground text-right mt-1">
                {message.length}/{MAX_MESSAGE_LENGTH}
              </p>
            </div>

            <DialogFooter>
              <Button
                variant="outline"
                onClick={() => handleClose(false)}
                disabled={isCreating}
              >
                Cancel
              </Button>
              <Button onClick={handleCreate} disabled={isCreating || !!emailError}>
                {isCreating ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Creating...
                  </>
                ) : (
                  'Create Invitation'
                )}
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
