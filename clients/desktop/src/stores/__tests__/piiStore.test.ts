import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { usePiiStore } from '../piiStore';

vi.mock('@/services/tauri', () => ({
  tauriService: {
    pii: {
      listConversations: vi.fn(),
      createConversation: vi.fn(),
      sendMessage: vi.fn(),
      registerKemKeys: vi.fn(),
      clearKemKeys: vi.fn(),
    },
  },
}));

const mockConversation = {
  id: 'conv-1',
  title: 'Test Conversation',
  llm_provider: 'anthropic',
  llm_model: 'claude-3-sonnet',
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
};

describe('piiStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    usePiiStore.setState({
      conversations: [],
      messages: new Map(),
      currentConversationId: null,
      kemKeysRegistered: new Map(),
      isLoading: false,
      isSending: false,
      isCreatingConversation: false,
      error: null,
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('initial state', () => {
    it('should have no conversations', () => {
      expect(usePiiStore.getState().conversations).toEqual([]);
    });

    it('should have no current conversation', () => {
      expect(usePiiStore.getState().currentConversationId).toBeNull();
    });

    it('should not be loading', () => {
      expect(usePiiStore.getState().isLoading).toBe(false);
    });
  });

  describe('selectConversation', () => {
    it('should set the current conversation ID', () => {
      usePiiStore.getState().selectConversation('conv-1');
      expect(usePiiStore.getState().currentConversationId).toBe('conv-1');
    });

    it('should set to null to deselect', () => {
      usePiiStore.getState().selectConversation('conv-1');
      usePiiStore.getState().selectConversation(null);
      expect(usePiiStore.getState().currentConversationId).toBeNull();
    });
  });

  describe('getCurrentConversation', () => {
    it('should return null when no conversation selected', () => {
      expect(usePiiStore.getState().getCurrentConversation()).toBeNull();
    });

    it('should return the current conversation', () => {
      usePiiStore.setState({
        conversations: [mockConversation],
        currentConversationId: 'conv-1',
      });
      expect(usePiiStore.getState().getCurrentConversation()?.id).toBe('conv-1');
    });
  });

  describe('getCurrentMessages', () => {
    it('should return empty array when no conversation selected', () => {
      expect(usePiiStore.getState().getCurrentMessages()).toEqual([]);
    });

    it('should return messages for current conversation', () => {
      const messages = new Map();
      messages.set('conv-1', [{ id: 'msg-1', content: 'Hello', role: 'user' }]);

      usePiiStore.setState({
        currentConversationId: 'conv-1',
        messages,
      });

      expect(usePiiStore.getState().getCurrentMessages()).toHaveLength(1);
    });
  });

  describe('clearError', () => {
    it('should clear the error state', () => {
      usePiiStore.setState({ error: 'some error' });
      usePiiStore.getState().clearError();
      expect(usePiiStore.getState().error).toBeNull();
    });
  });

  describe('deleteConversation', () => {
    it('should remove conversation from state', () => {
      usePiiStore.setState({
        conversations: [mockConversation],
        currentConversationId: 'conv-1',
      });

      usePiiStore.getState().deleteConversation('conv-1');

      const state = usePiiStore.getState();
      expect(state.conversations).toHaveLength(0);
      expect(state.currentConversationId).toBeNull();
    });

    it('should not affect current conversation if different one deleted', () => {
      const otherConv = { ...mockConversation, id: 'conv-2', title: 'Other' };
      usePiiStore.setState({
        conversations: [mockConversation, otherConv],
        currentConversationId: 'conv-1',
      });

      usePiiStore.getState().deleteConversation('conv-2');

      expect(usePiiStore.getState().currentConversationId).toBe('conv-1');
      expect(usePiiStore.getState().conversations).toHaveLength(1);
    });
  });
});
