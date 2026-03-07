import { create } from 'zustand';
import { tauriService } from '@/services/tauri';
import type { PiiConversation, DecryptedAskResponse } from '@/types';

// LLM Providers configuration
export const LLM_PROVIDERS = [
  {
    id: 'openai',
    name: 'OpenAI',
    models: ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo'],
  },
  {
    id: 'anthropic',
    name: 'Anthropic',
    models: ['claude-3-opus', 'claude-3-sonnet', 'claude-3-haiku'],
  },
  {
    id: 'google',
    name: 'Google',
    models: ['gemini-pro', 'gemini-pro-vision'],
  },
] as const;

export type LlmProviderId = (typeof LLM_PROVIDERS)[number]['id'];

// Message type for chat UI
export interface PiiMessage {
  id: string;
  conversationId: string;
  role: 'user' | 'assistant';
  content: string;
  tokenizedContent?: string;
  tokensDetected: number;
  createdAt: string;
}

interface PiiState {
  // State
  conversations: PiiConversation[];
  messages: Map<string, PiiMessage[]>; // conversationId -> messages
  currentConversationId: string | null;
  kemKeysRegistered: Map<string, boolean>; // conversationId -> registered
  isLoading: boolean;
  isSending: boolean;
  isCreatingConversation: boolean;
  error: string | null;

  // Computed
  getCurrentConversation: () => PiiConversation | null;
  getCurrentMessages: () => PiiMessage[];
  isCurrentKemRegistered: () => boolean;

  // Actions
  loadConversations: () => Promise<void>;
  createConversation: (
    title: string | undefined,
    llmProvider: string,
    llmModel: string
  ) => Promise<PiiConversation>;
  selectConversation: (conversationId: string | null) => void;
  registerKemKeys: (conversationId: string, includeKazKem?: boolean) => Promise<void>;
  sendMessage: (message: string, contextFiles?: string[]) => Promise<void>;
  clearKemKeys: () => Promise<void>;
  clearError: () => void;
  deleteConversation: (conversationId: string) => void;
}

export const usePiiStore = create<PiiState>((set, get) => ({
  // Initial state
  conversations: [],
  messages: new Map(),
  currentConversationId: null,
  kemKeysRegistered: new Map(),
  isLoading: false,
  isSending: false,
  isCreatingConversation: false,
  error: null,

  // Computed getters
  getCurrentConversation: () => {
    const { conversations, currentConversationId } = get();
    if (!currentConversationId) return null;
    return conversations.find((c) => c.id === currentConversationId) || null;
  },

  getCurrentMessages: () => {
    const { messages, currentConversationId } = get();
    if (!currentConversationId) return [];
    return messages.get(currentConversationId) || [];
  },

  isCurrentKemRegistered: () => {
    const { kemKeysRegistered, currentConversationId } = get();
    if (!currentConversationId) return false;
    return kemKeysRegistered.get(currentConversationId) || false;
  },

  // Actions
  loadConversations: async () => {
    set({ isLoading: true, error: null });
    try {
      const conversations = await tauriService.piiListConversations();
      // Sort by created_at descending (newest first)
      conversations.sort(
        (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      );
      set({ conversations, isLoading: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoading: false });
    }
  },

  createConversation: async (title, llmProvider, llmModel) => {
    set({ isCreatingConversation: true, error: null });
    try {
      const conversation = await tauriService.piiCreateConversation(
        llmProvider,
        llmModel,
        title
      );
      set((state) => ({
        conversations: [conversation, ...state.conversations],
        currentConversationId: conversation.id,
        isCreatingConversation: false,
      }));
      return conversation;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isCreatingConversation: false });
      throw error;
    }
  },

  selectConversation: (conversationId) => {
    set({ currentConversationId: conversationId });
  },

  registerKemKeys: async (conversationId, includeKazKem = true) => {
    set({ isLoading: true, error: null });
    try {
      await tauriService.piiRegisterKemKeys(conversationId, includeKazKem);
      set((state) => ({
        kemKeysRegistered: new Map(state.kemKeysRegistered).set(conversationId, true),
        isLoading: false,
      }));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoading: false });
      throw error;
    }
  },

  sendMessage: async (message, contextFiles) => {
    const { currentConversationId, kemKeysRegistered } = get();
    if (!currentConversationId) {
      set({ error: 'No conversation selected' });
      return;
    }

    // Auto-register KEM keys if not registered
    if (!kemKeysRegistered.get(currentConversationId)) {
      try {
        await get().registerKemKeys(currentConversationId, true);
      } catch {
        // Error already set by registerKemKeys
        return;
      }
    }

    set({ isSending: true, error: null });

    // Add optimistic user message
    const tempUserMessage: PiiMessage = {
      id: `temp-${Date.now()}`,
      conversationId: currentConversationId,
      role: 'user',
      content: message,
      tokensDetected: 0,
      createdAt: new Date().toISOString(),
    };

    set((state) => {
      const currentMessages = state.messages.get(currentConversationId) || [];
      return {
        messages: new Map(state.messages).set(currentConversationId, [
          ...currentMessages,
          tempUserMessage,
        ]),
      };
    });

    try {
      const response: DecryptedAskResponse = await tauriService.piiAsk(
        currentConversationId,
        message,
        contextFiles
      );

      // Replace temp message with real ones
      const userMessage: PiiMessage = {
        id: response.user_message_id,
        conversationId: currentConversationId,
        role: 'user',
        content: message,
        tokensDetected: response.tokens_detected,
        createdAt: response.created_at,
      };

      const assistantMessage: PiiMessage = {
        id: response.assistant_message_id,
        conversationId: currentConversationId,
        role: 'assistant',
        content: response.content,
        tokenizedContent: response.tokenized_content,
        tokensDetected: response.tokens_detected,
        createdAt: response.created_at,
      };

      set((state) => {
        const currentMessages = state.messages.get(currentConversationId) || [];
        // Remove temp message and add real messages
        const filteredMessages = currentMessages.filter(
          (m) => !m.id.startsWith('temp-')
        );
        return {
          messages: new Map(state.messages).set(currentConversationId, [
            ...filteredMessages,
            userMessage,
            assistantMessage,
          ]),
          isSending: false,
        };
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      // Remove optimistic message on error
      set((state) => {
        const currentMessages = state.messages.get(currentConversationId) || [];
        return {
          messages: new Map(state.messages).set(
            currentConversationId,
            currentMessages.filter((m) => !m.id.startsWith('temp-'))
          ),
          error: message,
          isSending: false,
        };
      });
    }
  },

  clearKemKeys: async () => {
    try {
      await tauriService.piiClearKemKeys();
      set({ kemKeysRegistered: new Map() });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
    }
  },

  clearError: () => set({ error: null }),

  deleteConversation: (conversationId) => {
    set((state) => {
      const newMessages = new Map(state.messages);
      newMessages.delete(conversationId);
      const newKemKeys = new Map(state.kemKeysRegistered);
      newKemKeys.delete(conversationId);
      return {
        conversations: state.conversations.filter((c) => c.id !== conversationId),
        messages: newMessages,
        kemKeysRegistered: newKemKeys,
        currentConversationId:
          state.currentConversationId === conversationId
            ? null
            : state.currentConversationId,
      };
    });
  },
}));
