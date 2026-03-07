import React, { useState, useEffect, useCallback } from 'react';
import { Search, Loader2, User } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog';
import { Button } from '../ui/Button';
import { Input } from '../ui/input';
import { Label } from '../ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '../ui/select';
import { useShareStore } from '../../stores/shareStore';
import { useToast } from '../../hooks/useToast';
import type { FileItem, SharePermission, RecipientSearchResult } from '../../types';

interface ShareDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: FileItem | null;
}

export function ShareDialog({ open, onOpenChange, item }: ShareDialogProps) {
  const [recipientEmail, setRecipientEmail] = useState('');
  const [selectedRecipient, setSelectedRecipient] = useState<RecipientSearchResult | null>(null);
  const [permission, setPermission] = useState<SharePermission>('read');
  const [message, setMessage] = useState('');
  const [showResults, setShowResults] = useState(false);

  const {
    searchResults,
    isSearching,
    isCreating,
    searchRecipients,
    createShare,
    clearSearch,
  } = useShareStore();

  const { success, error: showError } = useToast();

  // Debounced search
  useEffect(() => {
    const timer = setTimeout(() => {
      if (recipientEmail.length >= 2 && !selectedRecipient) {
        searchRecipients(recipientEmail);
        setShowResults(true);
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [recipientEmail, selectedRecipient, searchRecipients]);

  // Reset form when dialog closes
  useEffect(() => {
    if (!open) {
      setRecipientEmail('');
      setSelectedRecipient(null);
      setPermission('read');
      setMessage('');
      setShowResults(false);
      clearSearch();
    }
  }, [open, clearSearch]);

  const handleSelectRecipient = useCallback((recipient: RecipientSearchResult) => {
    setSelectedRecipient(recipient);
    setRecipientEmail(recipient.email);
    setShowResults(false);
    clearSearch();
  }, [clearSearch]);

  const handleEmailChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    setRecipientEmail(e.target.value);
    setSelectedRecipient(null);
  }, []);

  const handleShare = async () => {
    if (!item) return;

    const email = selectedRecipient?.email || recipientEmail;
    if (!email) {
      showError({ title: 'Please enter a recipient email' });
      return;
    }

    try {
      await createShare({
        item_id: item.id,
        recipient_email: email,
        permission,
        message: message || undefined,
      });

      success({
        title: 'Shared successfully',
        description: `${item.name} has been shared with ${email}`,
      });

      onOpenChange(false);
    } catch (err) {
      showError({
        title: 'Failed to share',
        description: String(err),
      });
    }
  };

  if (!item) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Share "{item.name}"</DialogTitle>
          <DialogDescription>
            Share this {item.type} with another user. They will receive an invitation.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-4">
          {/* Recipient Search */}
          <div className="space-y-2">
            <Label htmlFor="recipient">Recipient</Label>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                id="recipient"
                placeholder="Search by email or name..."
                value={recipientEmail}
                onChange={handleEmailChange}
                className="pl-9"
                autoComplete="off"
              />
              {isSearching && (
                <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" />
              )}

              {/* Search Results Dropdown */}
              {showResults && searchResults.length > 0 && (
                <div className="absolute z-10 mt-1 w-full rounded-md border bg-popover shadow-lg">
                  {searchResults.map((result) => (
                    <button
                      key={result.id}
                      type="button"
                      className="flex w-full items-center gap-3 px-3 py-2 text-left hover:bg-accent"
                      onClick={() => handleSelectRecipient(result)}
                    >
                      <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted">
                        <User className="h-4 w-4" />
                      </div>
                      <div className="flex-1 overflow-hidden">
                        <div className="truncate text-sm font-medium">{result.name}</div>
                        <div className="truncate text-xs text-muted-foreground">
                          {result.email}
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>
            {selectedRecipient && (
              <p className="text-xs text-muted-foreground">
                Selected: {selectedRecipient.name}
              </p>
            )}
          </div>

          {/* Permission Select */}
          <div className="space-y-2">
            <Label htmlFor="permission">Permission</Label>
            <Select value={permission} onValueChange={(v) => setPermission(v as SharePermission)}>
              <SelectTrigger id="permission">
                <SelectValue placeholder="Select permission" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="read">
                  <div>
                    <div className="font-medium">Read</div>
                    <div className="text-xs text-muted-foreground">Can view and download</div>
                  </div>
                </SelectItem>
                <SelectItem value="write">
                  <div>
                    <div className="font-medium">Write</div>
                    <div className="text-xs text-muted-foreground">Can view, download, and edit</div>
                  </div>
                </SelectItem>
                <SelectItem value="admin">
                  <div>
                    <div className="font-medium">Admin</div>
                    <div className="text-xs text-muted-foreground">Full access including re-sharing</div>
                  </div>
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          {/* Optional Message */}
          <div className="space-y-2">
            <Label htmlFor="message">Message (optional)</Label>
            <Input
              id="message"
              placeholder="Add a personal message..."
              value={message}
              onChange={(e) => setMessage(e.target.value)}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleShare} disabled={isCreating || !recipientEmail}>
            {isCreating && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Share
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
