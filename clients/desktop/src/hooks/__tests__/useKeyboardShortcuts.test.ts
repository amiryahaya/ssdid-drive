import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useKeyboardShortcuts, SHORTCUT_KEYS } from '../useKeyboardShortcuts';

describe('useKeyboardShortcuts', () => {
  let addEventListenerSpy: ReturnType<typeof vi.spyOn>;
  let removeEventListenerSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    addEventListenerSpy = vi.spyOn(window, 'addEventListener');
    removeEventListenerSpy = vi.spyOn(window, 'removeEventListener');
  });

  afterEach(() => {
    addEventListenerSpy.mockRestore();
    removeEventListenerSpy.mockRestore();
  });

  it('should register keydown event listener on mount', () => {
    const action = vi.fn();
    renderHook(() =>
      useKeyboardShortcuts([{ key: 'a', action }])
    );

    expect(addEventListenerSpy).toHaveBeenCalledWith(
      'keydown',
      expect.any(Function)
    );
  });

  it('should unregister event listener on unmount', () => {
    const action = vi.fn();
    const { unmount } = renderHook(() =>
      useKeyboardShortcuts([{ key: 'a', action }])
    );

    unmount();

    expect(removeEventListenerSpy).toHaveBeenCalledWith(
      'keydown',
      expect.any(Function)
    );
  });

  it('should call action when matching key is pressed', () => {
    const action = vi.fn();
    renderHook(() => useKeyboardShortcuts([{ key: 'a', action }]));

    act(() => {
      window.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'a' })
      );
    });

    expect(action).toHaveBeenCalledTimes(1);
  });

  it('should not call action when different key is pressed', () => {
    const action = vi.fn();
    renderHook(() => useKeyboardShortcuts([{ key: 'a', action }]));

    act(() => {
      window.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'b' })
      );
    });

    expect(action).not.toHaveBeenCalled();
  });

  it('should match Ctrl modifier', () => {
    const action = vi.fn();
    renderHook(() =>
      useKeyboardShortcuts([{ key: 'a', ctrl: true, action }])
    );

    // Without Ctrl - should not match
    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    });
    expect(action).not.toHaveBeenCalled();

    // With Ctrl - should match
    act(() => {
      window.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'a', ctrlKey: true })
      );
    });
    expect(action).toHaveBeenCalledTimes(1);
  });

  it('should match Meta key (Cmd on Mac) when ctrl is specified', () => {
    const action = vi.fn();
    renderHook(() =>
      useKeyboardShortcuts([{ key: 'a', ctrl: true, action }])
    );

    act(() => {
      window.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'a', metaKey: true })
      );
    });

    expect(action).toHaveBeenCalledTimes(1);
  });

  it('should match Shift modifier', () => {
    const action = vi.fn();
    renderHook(() =>
      useKeyboardShortcuts([{ key: 'a', shift: true, action }])
    );

    // Without Shift - should not match
    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    });
    expect(action).not.toHaveBeenCalled();

    // With Shift - should match
    act(() => {
      window.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'a', shiftKey: true })
      );
    });
    expect(action).toHaveBeenCalledTimes(1);
  });

  it('should match Alt modifier', () => {
    const action = vi.fn();
    renderHook(() =>
      useKeyboardShortcuts([{ key: 'a', alt: true, action }])
    );

    // Without Alt - should not match
    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    });
    expect(action).not.toHaveBeenCalled();

    // With Alt - should match
    act(() => {
      window.dispatchEvent(
        new KeyboardEvent('keydown', { key: 'a', altKey: true })
      );
    });
    expect(action).toHaveBeenCalledTimes(1);
  });

  it('should not trigger when typing in input', () => {
    const action = vi.fn();
    renderHook(() => useKeyboardShortcuts([{ key: 'a', action }]));

    const input = document.createElement('input');
    document.body.appendChild(input);
    input.focus();

    act(() => {
      const event = new KeyboardEvent('keydown', { key: 'a' });
      Object.defineProperty(event, 'target', { value: input });
      window.dispatchEvent(event);
    });

    expect(action).not.toHaveBeenCalled();
    document.body.removeChild(input);
  });

  it('should not trigger when typing in textarea', () => {
    const action = vi.fn();
    renderHook(() => useKeyboardShortcuts([{ key: 'a', action }]));

    const textarea = document.createElement('textarea');
    document.body.appendChild(textarea);

    act(() => {
      const event = new KeyboardEvent('keydown', { key: 'a' });
      Object.defineProperty(event, 'target', { value: textarea });
      window.dispatchEvent(event);
    });

    expect(action).not.toHaveBeenCalled();
    document.body.removeChild(textarea);
  });

  it('should not trigger when in contenteditable', () => {
    const action = vi.fn();
    renderHook(() => useKeyboardShortcuts([{ key: 'a', action }]));

    const div = document.createElement('div');
    div.contentEditable = 'true';
    document.body.appendChild(div);

    // Create a mock element with isContentEditable property
    const mockTarget = {
      tagName: 'DIV',
      isContentEditable: true,
    };

    act(() => {
      const event = new KeyboardEvent('keydown', { key: 'a' });
      Object.defineProperty(event, 'target', { value: mockTarget });
      window.dispatchEvent(event);
    });

    expect(action).not.toHaveBeenCalled();
    document.body.removeChild(div);
  });

  it('should handle multiple shortcuts', () => {
    const actionA = vi.fn();
    const actionB = vi.fn();
    renderHook(() =>
      useKeyboardShortcuts([
        { key: 'a', action: actionA },
        { key: 'b', action: actionB },
      ])
    );

    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    });

    expect(actionA).toHaveBeenCalledTimes(1);
    expect(actionB).not.toHaveBeenCalled();

    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'b' }));
    });

    expect(actionA).toHaveBeenCalledTimes(1);
    expect(actionB).toHaveBeenCalledTimes(1);
  });

  it('should be case insensitive for key matching', () => {
    const action = vi.fn();
    renderHook(() => useKeyboardShortcuts([{ key: 'A', action }]));

    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    });

    expect(action).toHaveBeenCalledTimes(1);
  });

  it('should respect enabled option', () => {
    const action = vi.fn();
    const { rerender } = renderHook(
      ({ enabled }) =>
        useKeyboardShortcuts([{ key: 'a', action }], { enabled }),
      { initialProps: { enabled: false } }
    );

    // Disabled - should not call action
    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    });
    expect(action).not.toHaveBeenCalled();

    // Enable
    rerender({ enabled: true });

    // Enabled - should call action
    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'a' }));
    });
    expect(action).toHaveBeenCalledTimes(1);
  });

  it('should prevent default when shortcut matches', () => {
    const action = vi.fn();
    renderHook(() => useKeyboardShortcuts([{ key: 'a', action }]));

    const event = new KeyboardEvent('keydown', { key: 'a' });
    const preventDefaultSpy = vi.spyOn(event, 'preventDefault');

    act(() => {
      window.dispatchEvent(event);
    });

    expect(preventDefaultSpy).toHaveBeenCalled();
  });

  it('should export predefined shortcut keys', () => {
    expect(SHORTCUT_KEYS.DELETE).toBe('Delete');
    expect(SHORTCUT_KEYS.BACKSPACE).toBe('Backspace');
    expect(SHORTCUT_KEYS.ESCAPE).toBe('Escape');
    expect(SHORTCUT_KEYS.F2).toBe('F2');
    expect(SHORTCUT_KEYS.A).toBe('a');
    expect(SHORTCUT_KEYS.D).toBe('d');
    expect(SHORTCUT_KEYS.QUESTION).toBe('?');
  });

  it('should handle special keys like Delete and Escape', () => {
    const deleteAction = vi.fn();
    const escapeAction = vi.fn();

    renderHook(() =>
      useKeyboardShortcuts([
        { key: SHORTCUT_KEYS.DELETE, action: deleteAction },
        { key: SHORTCUT_KEYS.ESCAPE, action: escapeAction },
      ])
    );

    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Delete' }));
    });
    expect(deleteAction).toHaveBeenCalledTimes(1);

    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    });
    expect(escapeAction).toHaveBeenCalledTimes(1);
  });
});
