import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useToast } from '../useToast';
import { useToastStore } from '../../stores/toastStore';

describe('useToast', () => {
  beforeEach(() => {
    useToastStore.setState({ toasts: [] });
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('should return toasts from store', () => {
    useToastStore.getState().addToast({ type: 'success', title: 'Test' });

    const { result } = renderHook(() => useToast());

    expect(result.current.toasts).toHaveLength(1);
    expect(result.current.toasts[0].title).toBe('Test');
  });

  describe('toast helper methods', () => {
    it('success() should add success toast', () => {
      const { result } = renderHook(() => useToast());

      act(() => {
        result.current.success({ title: 'Success!', description: 'Operation completed' });
      });

      const { toasts } = useToastStore.getState();
      expect(toasts).toHaveLength(1);
      expect(toasts[0].type).toBe('success');
      expect(toasts[0].title).toBe('Success!');
      expect(toasts[0].description).toBe('Operation completed');
    });

    it('error() should add error toast', () => {
      const { result } = renderHook(() => useToast());

      act(() => {
        result.current.error({ title: 'Error!' });
      });

      const { toasts } = useToastStore.getState();
      expect(toasts[0].type).toBe('error');
    });

    it('info() should add info toast', () => {
      const { result } = renderHook(() => useToast());

      act(() => {
        result.current.info({ title: 'Info' });
      });

      const { toasts } = useToastStore.getState();
      expect(toasts[0].type).toBe('info');
    });

    it('warning() should add warning toast', () => {
      const { result } = renderHook(() => useToast());

      act(() => {
        result.current.warning({ title: 'Warning' });
      });

      const { toasts } = useToastStore.getState();
      expect(toasts[0].type).toBe('warning');
    });
  });

  describe('dismiss methods', () => {
    it('dismiss() should remove specific toast', () => {
      const { result } = renderHook(() => useToast());

      act(() => {
        result.current.success({ title: 'Toast 1' });
        result.current.error({ title: 'Toast 2' });
      });

      const toastId = useToastStore.getState().toasts[0].id;

      act(() => {
        result.current.dismiss(toastId);
      });

      const { toasts } = useToastStore.getState();
      expect(toasts).toHaveLength(1);
      expect(toasts[0].title).toBe('Toast 2');
    });

    it('dismissAll() should remove all toasts', () => {
      const { result } = renderHook(() => useToast());

      act(() => {
        result.current.success({ title: 'Toast 1' });
        result.current.error({ title: 'Toast 2' });
        result.current.info({ title: 'Toast 3' });
      });

      expect(useToastStore.getState().toasts).toHaveLength(3);

      act(() => {
        result.current.dismissAll();
      });

      expect(useToastStore.getState().toasts).toHaveLength(0);
    });
  });

  it('toast() should add toast with specified type', () => {
    const { result } = renderHook(() => useToast());

    act(() => {
      result.current.toast('warning', { title: 'Custom type toast' });
    });

    const { toasts } = useToastStore.getState();
    expect(toasts[0].type).toBe('warning');
  });
});
