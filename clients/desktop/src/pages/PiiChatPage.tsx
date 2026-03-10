import { Bot, Lock } from 'lucide-react';

export function PiiChatPage() {
  return (
    <div className="flex flex-col items-center justify-center h-[calc(100vh-8rem)]">
      <div className="w-20 h-20 rounded-full bg-primary/10 flex items-center justify-center mb-6">
        <Bot className="h-10 w-10 text-primary" />
      </div>
      <h1 className="text-2xl font-semibold mb-2">AI Chat</h1>
      <span className="inline-flex items-center gap-1 px-3 py-1 text-sm font-medium rounded-full bg-amber-100 text-amber-800 dark:bg-amber-900/20 dark:text-amber-400 mb-4">
        Coming Soon
      </span>
      <p className="text-muted-foreground text-center max-w-md mb-2">
        Secure AI conversations with automatic PII redaction and post-quantum encryption.
      </p>
      <div className="flex items-center gap-2 text-xs text-muted-foreground">
        <Lock className="h-3 w-3" />
        <span>End-to-end encrypted with ML-KEM</span>
      </div>
    </div>
  );
}
