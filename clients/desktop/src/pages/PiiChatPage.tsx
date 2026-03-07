import { useEffect, useState } from 'react';
import { AlertCircle } from 'lucide-react';
import { usePiiStore } from '@/stores/piiStore';
import { ConversationList } from '@/components/pii/ConversationList';
import { ChatView } from '@/components/pii/ChatView';
import { NewConversationDialog } from '@/components/pii/NewConversationDialog';
import { Button } from '@/components/ui/Button';

export function PiiChatPage() {
  const {
    conversations,
    currentConversationId,
    isLoading,
    isSending,
    isCreatingConversation,
    error,
    loadConversations,
    createConversation,
    selectConversation,
    sendMessage,
    deleteConversation,
    clearError,
    getCurrentConversation,
    getCurrentMessages,
    isCurrentKemRegistered,
  } = usePiiStore();

  const [newConversationDialogOpen, setNewConversationDialogOpen] = useState(false);

  // Load conversations on mount
  useEffect(() => {
    loadConversations();
  }, [loadConversations]);

  const currentConversation = getCurrentConversation();
  const currentMessages = getCurrentMessages();
  const kemRegistered = isCurrentKemRegistered();

  const handleCreateConversation = async (
    title: string | undefined,
    llmProvider: string,
    llmModel: string
  ) => {
    await createConversation(title, llmProvider, llmModel);
  };

  return (
    <div className="flex flex-col h-[calc(100vh-8rem)]">
      {/* Error Banner */}
      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-red-800 dark:border-red-900 dark:bg-red-900/20 dark:text-red-400 mb-4">
          <AlertCircle className="h-5 w-5 flex-shrink-0" />
          <span className="flex-1">{error}</span>
          <Button size="sm" variant="ghost" onClick={clearError}>
            Dismiss
          </Button>
        </div>
      )}

      {/* Main content - two panel layout */}
      <div className="flex-1 flex border rounded-lg overflow-hidden bg-card">
        {/* Left panel - Conversation list */}
        <div className="w-80 border-r flex-shrink-0">
          <ConversationList
            conversations={conversations}
            currentConversationId={currentConversationId}
            isLoading={isLoading}
            onSelectConversation={selectConversation}
            onNewConversation={() => setNewConversationDialogOpen(true)}
            onDeleteConversation={deleteConversation}
          />
        </div>

        {/* Right panel - Chat view */}
        <div className="flex-1">
          <ChatView
            conversation={currentConversation}
            messages={currentMessages}
            isKemRegistered={kemRegistered}
            isSending={isSending}
            isLoading={isLoading}
            onSendMessage={sendMessage}
          />
        </div>
      </div>

      {/* New Conversation Dialog */}
      <NewConversationDialog
        open={newConversationDialogOpen}
        onOpenChange={setNewConversationDialogOpen}
        onCreateConversation={handleCreateConversation}
        isCreating={isCreatingConversation}
      />
    </div>
  );
}
