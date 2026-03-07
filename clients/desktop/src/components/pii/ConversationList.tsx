import { MessageSquarePlus, MessageSquare, Loader2, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { cn, formatDate } from '@/lib/utils';
import type { PiiConversation } from '@/types';
import { LLM_PROVIDERS } from '@/stores/piiStore';

interface ConversationListProps {
  conversations: PiiConversation[];
  currentConversationId: string | null;
  isLoading: boolean;
  onSelectConversation: (id: string) => void;
  onNewConversation: () => void;
  onDeleteConversation?: (id: string) => void;
}

export function ConversationList({
  conversations,
  currentConversationId,
  isLoading,
  onSelectConversation,
  onNewConversation,
  onDeleteConversation,
}: ConversationListProps) {
  const getProviderName = (providerId: string) => {
    const provider = LLM_PROVIDERS.find((p) => p.id === providerId);
    return provider?.name || providerId;
  };

  if (isLoading && conversations.length === 0) {
    return (
      <div className="flex flex-col h-full">
        <div className="p-4 border-b">
          <Button onClick={onNewConversation} className="w-full" disabled>
            <MessageSquarePlus className="h-4 w-4 mr-2" />
            New Chat
          </Button>
        </div>
        <div className="flex-1 flex items-center justify-center">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* New chat button */}
      <div className="p-4 border-b">
        <Button onClick={onNewConversation} className="w-full">
          <MessageSquarePlus className="h-4 w-4 mr-2" />
          New Chat
        </Button>
      </div>

      {/* Conversation list */}
      <div className="flex-1 overflow-y-auto">
        {conversations.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full p-6 text-center">
            <MessageSquare className="h-12 w-12 text-muted-foreground/50 mb-4" />
            <p className="text-sm text-muted-foreground">
              No conversations yet
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              Start a new chat to begin
            </p>
          </div>
        ) : (
          <div className="divide-y">
            {conversations.map((conversation) => (
              <div
                key={conversation.id}
                className={cn(
                  'p-4 cursor-pointer transition-colors hover:bg-muted/50 group relative',
                  currentConversationId === conversation.id && 'bg-muted'
                )}
                onClick={() => onSelectConversation(conversation.id)}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1 min-w-0">
                    <h3 className="font-medium truncate">
                      {conversation.title || 'Untitled Chat'}
                    </h3>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="text-xs px-1.5 py-0.5 rounded bg-muted-foreground/10 text-muted-foreground">
                        {getProviderName(conversation.llm_provider)}
                      </span>
                      <span className="text-xs text-muted-foreground truncate">
                        {conversation.llm_model}
                      </span>
                    </div>
                    <p className="text-xs text-muted-foreground mt-2">
                      {formatDate(conversation.created_at)}
                    </p>
                  </div>

                  {onDeleteConversation && (
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground hover:text-destructive"
                      onClick={(e) => {
                        e.stopPropagation();
                        onDeleteConversation(conversation.id);
                      }}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
