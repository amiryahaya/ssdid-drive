import { useState } from 'react';
import { Loader2, User, Pencil, Check, X } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { useAuthStore } from '@/stores/authStore';
import { useToast } from '@/hooks/useToast';

export function ProfileSection() {
  const { user, updateProfile } = useAuthStore();
  const [isEditing, setIsEditing] = useState(false);
  const [name, setName] = useState(user?.name || '');
  const [isSaving, setIsSaving] = useState(false);
  const { success, error: showError } = useToast();

  const handleEdit = () => {
    setName(user?.name || '');
    setIsEditing(true);
  };

  const handleCancel = () => {
    setName(user?.name || '');
    setIsEditing(false);
  };

  const handleSave = async () => {
    if (!name.trim()) {
      showError({ title: 'Name cannot be empty' });
      return;
    }

    if (name === user?.name) {
      setIsEditing(false);
      return;
    }

    setIsSaving(true);
    try {
      await updateProfile(name.trim());
      success({
        title: 'Profile updated',
        description: 'Your name has been updated successfully',
      });
      setIsEditing(false);
    } catch (err) {
      showError({
        title: 'Failed to update profile',
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setIsSaving(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleSave();
    } else if (e.key === 'Escape') {
      handleCancel();
    }
  };

  if (!user) {
    return null;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4 p-4 rounded-lg border">
        <div className="flex items-center justify-center h-12 w-12 rounded-full bg-primary/10 text-primary">
          <User className="h-6 w-6" />
        </div>
        <div className="flex-1 min-w-0">
          {isEditing ? (
            <div className="flex items-center gap-2">
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                onKeyDown={handleKeyDown}
                disabled={isSaving}
                className="h-8"
                autoFocus
              />
              <Button
                size="icon"
                variant="ghost"
                onClick={handleSave}
                disabled={isSaving}
                className="h-8 w-8 shrink-0"
              >
                {isSaving ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Check className="h-4 w-4 text-green-500" />
                )}
              </Button>
              <Button
                size="icon"
                variant="ghost"
                onClick={handleCancel}
                disabled={isSaving}
                className="h-8 w-8 shrink-0"
              >
                <X className="h-4 w-4 text-destructive" />
              </Button>
            </div>
          ) : (
            <div className="flex items-center gap-2">
              <p className="font-medium truncate">{user.name}</p>
              <Button
                size="icon"
                variant="ghost"
                onClick={handleEdit}
                className="h-6 w-6 shrink-0"
              >
                <Pencil className="h-3 w-3" />
              </Button>
            </div>
          )}
          <p className="text-sm text-muted-foreground truncate">{user.email}</p>
        </div>
      </div>
    </div>
  );
}
