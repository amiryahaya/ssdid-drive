import { useEffect, useRef } from 'react';
import { MessageSquare, Loader2, ShieldCheck } from 'lucide-react';
import { ChatMessage } from './ChatMessage';
import { ChatInput } from './ChatInput';
import { KemKeyStatus } from './KemKeyStatus';
import type { PiiMessage } from '@/stores/piiStore';
import type { PiiConversation } from '@/types';
import { LLM_PROVIDERS } from '@/stores/piiStore';

interface ChatViewProps {
  conversation: PiiConversation | null;
  messages: PiiMessage[];
  isKemRegistered: boolean;
  isSending: boolean;
  isLoading: boolean;
  onSendMessage: (message: string) => void;
}

export function ChatView({
  conversation,
  messages,
  isKemRegistered,
  isSending,
  isLoading,
  onSendMessage,
}: ChatViewProps) {
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const getProviderName = (providerId: string) => {
    const provider = LLM_PROVIDERS.find((p) => p.id === providerId);
    return provider?.name || providerId;
  };

  // Empty state - no conversation selected
  if (!conversation) {
    return (
      <div className="flex flex-col items-center justify-center h-full text-center p-6">
        <div className="w-16 h-16 rounded-full bg-primary/10 flex items-center justify-center mb-4">
          <ShieldCheck className="h-8 w-8 text-primary" />
        </div>
        <h2 className="text-xl font-semibold mb-2">Secure AI Chat</h2>
        <p className="text-muted-foreground max-w-md mb-6">
          Have secure conversations with AI assistants. Your personal information
          is automatically detected and protected with post-quantum encryption.
        </p>
        <div className="text-sm text-muted-foreground">
          Select a conversation or start a new chat to begin.
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* Chat header */}
      <div className="flex-shrink-0 border-b p-4">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="font-semibold">
              {conversation.title || 'Untitled Chat'}
            </h2>
            <div className="flex items-center gap-2 mt-1">
              <span className="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground">
                {getProviderName(conversation.llm_provider)}
              </span>
              <span className="text-xs text-muted-foreground">
                {conversation.llm_model}
              </span>
            </div>
          </div>
          <KemKeyStatus isRegistered={isKemRegistered} isLoading={isLoading} />
        </div>
      </div>

      {/* Messages area */}
      <div className="flex-1 overflow-y-auto">
        {messages.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center p-6">
            <MessageSquare className="h-12 w-12 text-muted-foreground/50 mb-4" />
            <p className="text-muted-foreground">
              No messages yet. Start the conversation!
            </p>
            <p className="text-sm text-muted-foreground mt-2">
              Your messages will be scanned for PII and protected automatically.
            </p>
          </div>
        ) : (
          <div className="divide-y">
            {messages.map((message) => (
              <ChatMessage key={message.id} message={message} />
            ))}

            {/* Typing indicator */}
            {isSending && (
              <div className="flex items-center gap-3 p-4">
                <div className="w-8 h-8 rounded-full bg-muted flex items-center justify-center">
                  <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                </div>
                <div className="text-sm text-muted-foreground">
                  AI is thinking...
                </div>
              </div>
            )}

            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Message input */}
      <ChatInput
        onSend={onSendMessage}
        isSending={isSending}
        placeholder="Type your message... (PII will be protected)"
      />
    </div>
  );
}
