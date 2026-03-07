import { useState, useRef, useEffect, useCallback } from 'react';
import { Send, Lock, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { cn } from '@/lib/utils';

interface ChatInputProps {
  onSend: (message: string) => void;
  isSending: boolean;
  disabled?: boolean;
  placeholder?: string;
}

export function ChatInput({
  onSend,
  isSending,
  disabled = false,
  placeholder = 'Type a message...',
}: ChatInputProps) {
  const [message, setMessage] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Auto-resize textarea
  useEffect(() => {
    const textarea = textareaRef.current;
    if (textarea) {
      textarea.style.height = 'auto';
      textarea.style.height = `${Math.min(textarea.scrollHeight, 200)}px`;
    }
  }, [message]);

  const handleSend = useCallback(() => {
    const trimmed = message.trim();
    if (trimmed && !isSending && !disabled) {
      onSend(trimmed);
      setMessage('');
      // Reset textarea height
      if (textareaRef.current) {
        textareaRef.current.style.height = 'auto';
      }
    }
  }, [message, isSending, disabled, onSend]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Send on Cmd/Ctrl + Enter
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      handleSend();
    }
  };

  const canSend = message.trim().length > 0 && !isSending && !disabled;

  return (
    <div className="border-t bg-background p-4">
      <div className="flex items-end gap-2">
        <div className="relative flex-1">
          <textarea
            ref={textareaRef}
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
            disabled={disabled || isSending}
            rows={1}
            className={cn(
              'w-full resize-none rounded-lg border bg-background px-4 py-3 pr-10',
              'focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent',
              'placeholder:text-muted-foreground',
              'disabled:opacity-50 disabled:cursor-not-allowed',
              'min-h-[48px] max-h-[200px]'
            )}
          />
          {/* Security indicator */}
          <div className="absolute right-3 bottom-3 text-muted-foreground">
            <Lock className="h-4 w-4" />
          </div>
        </div>

        <Button
          onClick={handleSend}
          disabled={!canSend}
          size="icon"
          className="h-12 w-12 rounded-lg flex-shrink-0"
        >
          {isSending ? (
            <Loader2 className="h-5 w-5 animate-spin" />
          ) : (
            <Send className="h-5 w-5" />
          )}
        </Button>
      </div>

      {/* Keyboard hint */}
      <p className="text-xs text-muted-foreground mt-2 text-center">
        Press{' '}
        <kbd className="px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono text-xs">
          {navigator.platform.includes('Mac') ? 'Cmd' : 'Ctrl'}+Enter
        </kbd>{' '}
        to send
      </p>
    </div>
  );
}
