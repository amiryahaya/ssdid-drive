import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook } from '@testing-library/react';
import { useDeepLink } from '../useDeepLink';

const mockNavigate = vi.fn();
const mockUnlisten = vi.fn();
const mockSuccess = vi.fn();
const mockError = vi.fn();
const mockInfo = vi.fn();

vi.mock('react-router-dom', () => ({
  useNavigate: () => mockNavigate,
}));

vi.mock('@tauri-apps/api/event', () => ({
  listen: vi.fn(() => Promise.resolve(mockUnlisten)),
}));

vi.mock('@/stores/authStore', () => ({
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  useAuthStore: vi.fn((selector: any) => {
    const state = { isAuthenticated: true, user: { id: 'user-1' } };
    return selector ? selector(state) : state;
  }),
}));

vi.mock('../useToast', () => ({
  useToast: () => ({
    success: mockSuccess,
    error: mockError,
    info: mockInfo,
  }),
}));

describe('useDeepLink', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('hook initialization', () => {
    it('should return handleDeepLink and parseDeepLink functions', () => {
      const { result } = renderHook(() => useDeepLink());
      expect(result.current.handleDeepLink).toBeInstanceOf(Function);
      expect(result.current.parseDeepLink).toBeInstanceOf(Function);
    });
  });

  describe('handleDeepLink', () => {
    it('should navigate to /shared-with-me with share ID for share links', async () => {
      const { result } = renderHook(() => useDeepLink());

      await result.current.handleDeepLink('ssdid-drive://share/share-123');

      expect(mockNavigate).toHaveBeenCalledWith('/shared-with-me', {
        state: { highlightShare: 'share-123' },
      });
    });

    it('should navigate to /files with openFile state for file links', async () => {
      const { result } = renderHook(() => useDeepLink());

      await result.current.handleDeepLink('ssdid-drive://file/file-456');

      expect(mockNavigate).toHaveBeenCalledWith('/files', {
        state: { openFile: 'file-456' },
      });
    });

    it('should navigate to /files/{folderId} for folder links', async () => {
      const { result } = renderHook(() => useDeepLink());

      await result.current.handleDeepLink('ssdid-drive://folder/folder-789');

      expect(mockNavigate).toHaveBeenCalledWith('/files/folder-789');
    });

    it('should navigate to /register with invite token for invite links', async () => {
      const { result } = renderHook(() => useDeepLink());

      await result.current.handleDeepLink('ssdid-drive://invite/token-abc');

      expect(mockNavigate).toHaveBeenCalledWith('/register?invite=token-abc');
    });

    it('should navigate to /settings with recovery state for recovery links', async () => {
      const { result } = renderHook(() => useDeepLink());

      await result.current.handleDeepLink('ssdid-drive://recovery/req-001');

      expect(mockNavigate).toHaveBeenCalledWith('/settings', {
        state: { section: 'recovery', requestId: 'req-001' },
      });
    });

    it('should show error toast for unknown deep link actions', async () => {
      const { result } = renderHook(() => useDeepLink());

      await result.current.handleDeepLink('ssdid-drive://unknown/something');

      expect(mockError).toHaveBeenCalledWith(
        expect.objectContaining({ title: 'Invalid link' })
      );
      expect(mockNavigate).not.toHaveBeenCalled();
    });
  });

  describe('parseDeepLink', () => {
    it('should parse share deep links', () => {
      const { result } = renderHook(() => useDeepLink());
      const parsed = result.current.parseDeepLink('ssdid-drive://share/abc-123');
      expect(parsed).toEqual({ action: 'share', id: 'abc-123', params: {} });
    });

    it('should parse deep links with query parameters', () => {
      const { result } = renderHook(() => useDeepLink());
      const parsed = result.current.parseDeepLink('ssdid-drive://invite/tok?source=email');
      expect(parsed).toEqual({ action: 'invite', id: 'tok', params: { source: 'email' } });
    });

    it('should return unknown for malformed deep links', () => {
      const { result } = renderHook(() => useDeepLink());
      const parsed = result.current.parseDeepLink('ssdid-drive://');
      expect(parsed.action).toBe('unknown');
    });
  });

  describe('unauthenticated user', () => {
    it('should redirect to login and store pending deep link', async () => {
      // Re-mock authStore to return unauthenticated
      const { useAuthStore } = await import('@/stores/authStore');
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (useAuthStore as any).mockImplementation((selector: any) => {
        const state = { isAuthenticated: false, user: null };
        return selector ? selector(state) : state;
      });

      const { result } = renderHook(() => useDeepLink());

      await result.current.handleDeepLink('ssdid-drive://file/file-789');

      expect(mockNavigate).toHaveBeenCalledWith('/login');
      expect(sessionStorage.getItem('pendingDeepLink')).toBe('ssdid-drive://file/file-789');

      // Clean up
      sessionStorage.removeItem('pendingDeepLink');
    });
  });
});
