import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { useToastStore } from '../toastStore';

describe('toastStore', () => {
  beforeEach(() => {
    // Reset the store state before each test
    useToastStore.setState({ toasts: [] });
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('addToast', () => {
    it('should add a toast with unique ID', () => {
      const { addToast } = useToastStore.getState();

      addToast({ type: 'success', title: 'Test Toast' });

      const { toasts } = useToastStore.getState();
      expect(toasts).toHaveLength(1);
      expect(toasts[0]).toMatchObject({
        type: 'success',
        title: 'Test Toast',
      });
      expect(toasts[0].id).toMatch(/^toast-\d+$/);
    });

    it('should add multiple toasts with unique IDs', () => {
      const { addToast } = useToastStore.getState();

      addToast({ type: 'success', title: 'Toast 1' });
      addToast({ type: 'error', title: 'Toast 2' });
      addToast({ type: 'info', title: 'Toast 3' });

      const { toasts } = useToastStore.getState();
      expect(toasts).toHaveLength(3);

      const ids = toasts.map((t) => t.id);
      expect(new Set(ids).size).toBe(3); // All IDs are unique
    });

    it('should include optional description', () => {
      const { addToast } = useToastStore.getState();

      addToast({
        type: 'warning',
        title: 'Warning',
        description: 'This is a warning message',
      });

      const { toasts } = useToastStore.getState();
      expect(toasts[0].description).toBe('This is a warning message');
    });
  });

  describe('removeToast', () => {
    it('should remove a specific toast by ID', () => {
      const { addToast, removeToast } = useToastStore.getState();

      addToast({ type: 'success', title: 'Toast 1' });
      addToast({ type: 'error', title: 'Toast 2' });

      const { toasts: initialToasts } = useToastStore.getState();
      const toastIdToRemove = initialToasts[0].id;

      removeToast(toastIdToRemove);

      const { toasts: finalToasts } = useToastStore.getState();
      expect(finalToasts).toHaveLength(1);
      expect(finalToasts[0].title).toBe('Toast 2');
    });

    it('should do nothing when removing non-existent ID', () => {
      const { addToast, removeToast } = useToastStore.getState();

      addToast({ type: 'success', title: 'Toast 1' });

      removeToast('non-existent-id');

      const { toasts } = useToastStore.getState();
      expect(toasts).toHaveLength(1);
    });
  });

  describe('clearToasts', () => {
    it('should remove all toasts', () => {
      const { addToast, clearToasts } = useToastStore.getState();

      addToast({ type: 'success', title: 'Toast 1' });
      addToast({ type: 'error', title: 'Toast 2' });
      addToast({ type: 'info', title: 'Toast 3' });

      expect(useToastStore.getState().toasts).toHaveLength(3);

      clearToasts();

      expect(useToastStore.getState().toasts).toHaveLength(0);
    });
  });

  describe('auto-dismiss', () => {
    it('should auto-remove toast after default duration', () => {
      const { addToast } = useToastStore.getState();

      addToast({ type: 'success', title: 'Auto-dismiss toast' });

      expect(useToastStore.getState().toasts).toHaveLength(1);

      // Fast-forward time past default duration (5000ms)
      vi.advanceTimersByTime(5000);

      expect(useToastStore.getState().toasts).toHaveLength(0);
    });

    it('should auto-remove toast after custom duration', () => {
      const { addToast } = useToastStore.getState();

      addToast({ type: 'success', title: 'Custom duration', duration: 2000 });

      expect(useToastStore.getState().toasts).toHaveLength(1);

      vi.advanceTimersByTime(1999);
      expect(useToastStore.getState().toasts).toHaveLength(1);

      vi.advanceTimersByTime(1);
      expect(useToastStore.getState().toasts).toHaveLength(0);
    });

    it('should not auto-dismiss when duration is 0', () => {
      const { addToast } = useToastStore.getState();

      addToast({ type: 'success', title: 'Persistent toast', duration: 0 });

      vi.advanceTimersByTime(10000);

      expect(useToastStore.getState().toasts).toHaveLength(1);
    });
  });
});
