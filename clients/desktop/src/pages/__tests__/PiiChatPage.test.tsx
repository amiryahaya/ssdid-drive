import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../test/utils';
import { PiiChatPage } from '../PiiChatPage';
import { usePiiStore } from '../../stores/piiStore';

vi.mock('../../components/pii/ConversationList', () => ({
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ConversationList: ({ conversations, onSelect, onNew }: any) => (
    <div data-testid="conversation-list">
      {/* eslint-disable-next-line @typescript-eslint/no-explicit-any */}
      {conversations?.map((c: any) => (
        <button key={c.id} onClick={() => onSelect(c.id)}>
          {c.title}
        </button>
      ))}
      <button onClick={onNew} data-testid="new-conversation">
        New
      </button>
    </div>
  ),
}));

vi.mock('../../components/pii/ChatView', () => ({
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ChatView: ({ conversation }: any) => (
    <div data-testid="chat-view">
      {conversation ? conversation.title : 'No conversation selected'}
    </div>
  ),
}));

vi.mock('../../components/pii/NewConversationDialog', () => ({
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  NewConversationDialog: ({ open, onClose }: any) =>
    open ? (
      <div data-testid="new-conversation-dialog">
        <button onClick={onClose}>Cancel</button>
      </div>
    ) : null,
}));

describe('PiiChatPage', () => {
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

  describe('rendering', () => {
    it('should render the conversation list', () => {
      render(<PiiChatPage />);
      expect(screen.getByTestId('conversation-list')).toBeInTheDocument();
    });

    it('should render the chat view', () => {
      render(<PiiChatPage />);
      expect(screen.getByTestId('chat-view')).toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('should show error banner when error exists', () => {
      // Override loadConversations to not clear the error on mount
      usePiiStore.setState({
        error: 'Failed to load conversations',
        loadConversations: async () => {},
      });
      render(<PiiChatPage />);
      expect(screen.getByText('Failed to load conversations')).toBeInTheDocument();
    });
  });

  describe('with conversations', () => {
    it('should display conversations in the list', () => {
      usePiiStore.setState({
        conversations: [
          {
            id: 'conv-1',
            title: 'Test Chat',
            llm_provider: 'anthropic',
            llm_model: 'claude-3',
            created_at: '2026-01-01T00:00:00Z',
            updated_at: '2026-01-01T00:00:00Z',
          },
        ],
      });

      render(<PiiChatPage />);
      expect(screen.getByText('Test Chat')).toBeInTheDocument();
    });
  });

  describe('no conversation selected', () => {
    it('should show placeholder in chat view', () => {
      render(<PiiChatPage />);
      expect(screen.getByText('No conversation selected')).toBeInTheDocument();
    });
  });
});
