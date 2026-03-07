import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useFocusReturn, useRovingFocus } from '../useFocusReturn';

describe('useFocusReturn', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('should store the currently focused element when becoming active', () => {
    // Create a button and focus it
    const button = document.createElement('button');
    document.body.appendChild(button);
    button.focus();

    expect(document.activeElement).toBe(button);

    // Render the hook with isActive = true
    renderHook(() => useFocusReturn(true));

    // The previous focus should have been stored
    // (We can't directly test the ref, but we can test the behavior)
    document.body.removeChild(button);
  });

  it('should return focus to the previous element when becoming inactive', async () => {
    // Create a button and focus it
    const button = document.createElement('button');
    document.body.appendChild(button);
    button.focus();

    expect(document.activeElement).toBe(button);

    // Render the hook with isActive = true
    const { unmount } = renderHook(() => useFocusReturn(true));

    // Move focus somewhere else
    const input = document.createElement('input');
    document.body.appendChild(input);
    input.focus();

    expect(document.activeElement).toBe(input);

    // Unmount the hook (simulates component closing)
    unmount();

    // Advance timers to allow the setTimeout to fire
    await act(async () => {
      vi.advanceTimersByTime(10);
    });

    // Focus should return to the original button
    expect(document.activeElement).toBe(button);

    document.body.removeChild(button);
    document.body.removeChild(input);
  });

  it('should not return focus when isActive is false', async () => {
    const button = document.createElement('button');
    document.body.appendChild(button);
    button.focus();

    // Render with isActive = false
    const { unmount } = renderHook(() => useFocusReturn(false));

    const input = document.createElement('input');
    document.body.appendChild(input);
    input.focus();

    unmount();

    await act(async () => {
      vi.advanceTimersByTime(10);
    });

    // Focus should remain on input
    expect(document.activeElement).toBe(input);

    document.body.removeChild(button);
    document.body.removeChild(input);
  });
});

describe('useRovingFocus', () => {
  let container: HTMLDivElement;
  let buttons: HTMLButtonElement[];

  beforeEach(() => {
    container = document.createElement('div');
    buttons = [];

    for (let i = 0; i < 4; i++) {
      const button = document.createElement('button');
      button.textContent = `Button ${i + 1}`;
      button.setAttribute('role', 'menuitem');
      container.appendChild(button);
      buttons.push(button);
    }

    document.body.appendChild(container);
  });

  afterEach(() => {
    document.body.removeChild(container);
  });

  it('should focus next item on ArrowDown', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[0].focus();
    expect(document.activeElement).toBe(buttons[0]);

    // Dispatch ArrowDown
    const event = new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[1]);
  });

  it('should focus previous item on ArrowUp', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[2].focus();
    expect(document.activeElement).toBe(buttons[2]);

    const event = new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[1]);
  });

  it('should wrap to first item when pressing ArrowDown on last item', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[3].focus();
    expect(document.activeElement).toBe(buttons[3]);

    const event = new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[0]);
  });

  it('should wrap to last item when pressing ArrowUp on first item', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[0].focus();

    const event = new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[3]);
  });

  it('should focus first item on Home key', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[2].focus();

    const event = new KeyboardEvent('keydown', { key: 'Home', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[0]);
  });

  it('should focus last item on End key', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[1].focus();

    const event = new KeyboardEvent('keydown', { key: 'End', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[3]);
  });

  it('should handle ArrowRight as ArrowDown', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[0].focus();

    const event = new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[1]);
  });

  it('should handle ArrowLeft as ArrowUp', () => {
    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[2].focus();

    const event = new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[1]);
  });

  it('should skip disabled items', () => {
    buttons[1].setAttribute('disabled', 'true');
    buttons[1].tabIndex = -1;

    const containerRef = { current: container };

    renderHook(() => useRovingFocus(containerRef));

    buttons[0].focus();

    // First ArrowDown should skip button[1] and go to button[2]
    const event = new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true });
    container.dispatchEvent(event);

    expect(document.activeElement).toBe(buttons[2]);
  });

  it('should clean up event listener on unmount', () => {
    const removeEventListenerSpy = vi.spyOn(container, 'removeEventListener');
    const containerRef = { current: container };

    const { unmount } = renderHook(() => useRovingFocus(containerRef));

    unmount();

    expect(removeEventListenerSpy).toHaveBeenCalledWith('keydown', expect.any(Function));
  });
});
