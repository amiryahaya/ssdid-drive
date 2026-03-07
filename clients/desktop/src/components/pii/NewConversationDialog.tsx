import { useState, useMemo } from 'react';
import { ShieldCheck, Loader2 } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { LLM_PROVIDERS, type LlmProviderId } from '@/stores/piiStore';

interface NewConversationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreateConversation: (
    title: string | undefined,
    llmProvider: string,
    llmModel: string
  ) => Promise<void>;
  isCreating: boolean;
}

export function NewConversationDialog({
  open,
  onOpenChange,
  onCreateConversation,
  isCreating,
}: NewConversationDialogProps) {
  const [title, setTitle] = useState('');
  const [provider, setProvider] = useState<LlmProviderId>('openai');
  const [model, setModel] = useState('gpt-4o');

  // Get available models for selected provider
  const availableModels = useMemo(() => {
    const selectedProvider = LLM_PROVIDERS.find((p) => p.id === provider);
    return selectedProvider?.models || [];
  }, [provider]);

  // Update model when provider changes
  const handleProviderChange = (newProvider: LlmProviderId) => {
    setProvider(newProvider);
    const selectedProvider = LLM_PROVIDERS.find((p) => p.id === newProvider);
    if (selectedProvider && selectedProvider.models.length > 0) {
      setModel(selectedProvider.models[0]);
    }
  };

  const handleCreate = async () => {
    try {
      await onCreateConversation(title.trim() || undefined, provider, model);
      // Reset form
      setTitle('');
      setProvider('openai');
      setModel('gpt-4o');
      onOpenChange(false);
    } catch {
      // Error is handled by the store
    }
  };

  const handleOpenChange = (newOpen: boolean) => {
    if (!isCreating) {
      onOpenChange(newOpen);
      if (!newOpen) {
        // Reset form when closing
        setTitle('');
        setProvider('openai');
        setModel('gpt-4o');
      }
    }
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>New Conversation</DialogTitle>
          <DialogDescription>
            Start a secure conversation with an AI assistant. Your data is protected
            with post-quantum encryption.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-4">
          {/* Title input */}
          <div className="space-y-2">
            <Label htmlFor="title">Title (optional)</Label>
            <Input
              id="title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Enter a title for this conversation"
              disabled={isCreating}
            />
          </div>

          {/* Provider select */}
          <div className="space-y-2">
            <Label htmlFor="provider">AI Provider</Label>
            <Select
              value={provider}
              onValueChange={(value) => handleProviderChange(value as LlmProviderId)}
              disabled={isCreating}
            >
              <SelectTrigger id="provider">
                <SelectValue placeholder="Select a provider" />
              </SelectTrigger>
              <SelectContent>
                {LLM_PROVIDERS.map((p) => (
                  <SelectItem key={p.id} value={p.id}>
                    {p.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Model select */}
          <div className="space-y-2">
            <Label htmlFor="model">Model</Label>
            <Select
              value={model}
              onValueChange={setModel}
              disabled={isCreating}
            >
              <SelectTrigger id="model">
                <SelectValue placeholder="Select a model" />
              </SelectTrigger>
              <SelectContent>
                {availableModels.map((m) => (
                  <SelectItem key={m} value={m}>
                    {m}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Security info banner */}
          <div className="rounded-lg bg-green-50 dark:bg-green-900/20 p-3 flex items-start gap-3">
            <ShieldCheck className="h-5 w-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm text-green-800 dark:text-green-300">
              <p className="font-medium">Post-quantum encryption enabled</p>
              <p className="text-green-700 dark:text-green-400 mt-1">
                Your personal information will be automatically detected, tokenized,
                and protected using ML-KEM and KAZ-KEM encryption.
              </p>
            </div>
          </div>
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => handleOpenChange(false)}
            disabled={isCreating}
          >
            Cancel
          </Button>
          <Button onClick={handleCreate} disabled={isCreating}>
            {isCreating && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
            Create Conversation
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
