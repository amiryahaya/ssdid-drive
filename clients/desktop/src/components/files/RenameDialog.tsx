import React, { useState, useEffect } from 'react';
import { Loader2, Pencil } from 'lucide-react';
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
import type { FileItem } from '../../types';

interface RenameDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: FileItem | null;
  onRename: (itemId: string, newName: string) => Promise<void>;
}

export function RenameDialog({
  open,
  onOpenChange,
  item,
  onRename,
}: RenameDialogProps) {
  const [name, setName] = useState('');
  const [isRenaming, setIsRenaming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Set initial name when item changes
  useEffect(() => {
    if (item) {
      setName(item.name);
    }
  }, [item]);

  // Reset error when dialog opens/closes
  useEffect(() => {
    if (!open) {
      setError(null);
    }
  }, [open]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!item) return;

    const trimmedName = name.trim();
    if (!trimmedName) {
      setError('Please enter a name');
      return;
    }

    // Check if name is the same
    if (trimmedName === item.name) {
      onOpenChange(false);
      return;
    }

    // Basic validation
    if (/[<>:"/\\|?*]/.test(trimmedName)) {
      setError('Name contains invalid characters');
      return;
    }

    setIsRenaming(true);
    setError(null);

    try {
      await onRename(item.id, trimmedName);
      onOpenChange(false);
    } catch (err) {
      setError(String(err));
    } finally {
      setIsRenaming(false);
    }
  };

  if (!item) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[400px]">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Pencil className="h-5 w-5" />
              Rename {item.type === 'folder' ? 'Folder' : 'File'}
            </DialogTitle>
            <DialogDescription>
              Enter a new name for "{item.name}".
            </DialogDescription>
          </DialogHeader>

          <div className="py-4">
            <div className="space-y-2">
              <Label htmlFor="item-name">Name</Label>
              <Input
                id="item-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                autoFocus
                autoComplete="off"
                onFocus={(e) => {
                  // Select filename without extension for files
                  if (item.type === 'file') {
                    const lastDot = name.lastIndexOf('.');
                    if (lastDot > 0) {
                      e.target.setSelectionRange(0, lastDot);
                    } else {
                      e.target.select();
                    }
                  } else {
                    e.target.select();
                  }
                }}
              />
              {error && (
                <p className="text-sm text-red-500">{error}</p>
              )}
            </div>
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={isRenaming || !name.trim()}>
              {isRenaming && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Rename
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
