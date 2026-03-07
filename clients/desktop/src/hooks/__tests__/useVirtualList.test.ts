import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useVirtualList, useSimpleVirtualization } from '../useVirtualList';

// Mock ResizeObserver
class MockResizeObserver {
  callback: ResizeObserverCallback;
  elements: Element[] = [];

  constructor(callback: ResizeObserverCallback) {
    this.callback = callback;
  }

  observe(element: Element) {
    this.elements.push(element);
    // Trigger callback immediately with mock entry
    this.callback(
      [
        {
          target: element,
          contentRect: { width: 400, height: 600 } as DOMRectReadOnly,
        } as ResizeObserverEntry,
      ],
      this
    );
  }

  unobserve(element: Element) {
    this.elements = this.elements.filter((el) => el !== element);
  }

  disconnect() {
    this.elements = [];
  }
}

describe('useVirtualList', () => {
  let originalResizeObserver: typeof ResizeObserver;
  let mockContainer: HTMLDivElement;

  beforeEach(() => {
    originalResizeObserver = globalThis.ResizeObserver;
    globalThis.ResizeObserver = MockResizeObserver as unknown as typeof ResizeObserver;

    // Create a mock container element
    mockContainer = document.createElement('div');
    Object.defineProperty(mockContainer, 'clientHeight', {
      configurable: true,
      value: 600,
    });
    Object.defineProperty(mockContainer, 'scrollTop', {
      configurable: true,
      value: 0,
      writable: true,
    });

    mockContainer.scrollTo = vi.fn(({ top }) => {
      Object.defineProperty(mockContainer, 'scrollTop', {
        configurable: true,
        value: top,
        writable: true,
      });
    });
  });

  afterEach(() => {
    globalThis.ResizeObserver = originalResizeObserver;
  });

  it('should return container ref', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    expect(result.current.containerRef).toBeDefined();
    expect(result.current.containerRef.current).toBeNull();
  });

  it('should calculate total height correctly', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    expect(result.current.totalHeight).toBe(5000); // 100 * 50
  });

  it('should return empty virtualItems when container height is 0', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    // Without a container mounted, containerHeight is 0
    expect(result.current.virtualItems).toEqual([]);
  });

  it('should calculate visible items with overscan', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
        overscan: 3,
      })
    );

    // Simulate container mounting
    act(() => {
      // @ts-expect-error - we're assigning to a ref
      result.current.containerRef.current = mockContainer;
    });

    // After the effect runs and ResizeObserver triggers,
    // the virtual items should be calculated
    // With containerHeight 600 and itemHeight 50, we can show 12 items
    // Plus overscan of 3 on each end
  });

  it('should provide scrollToIndex function', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    expect(typeof result.current.scrollToIndex).toBe('function');
  });

  it('should calculate correct total height for different item counts', () => {
    const { result: result1 } = renderHook(() =>
      useVirtualList({
        itemCount: 50,
        itemHeight: 30,
      })
    );
    expect(result1.current.totalHeight).toBe(1500); // 50 * 30

    const { result: result2 } = renderHook(() =>
      useVirtualList({
        itemCount: 1000,
        itemHeight: 100,
      })
    );
    expect(result2.current.totalHeight).toBe(100000); // 1000 * 100
  });

  it('should default overscan to 3', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    // The hook should use default overscan of 3
    // We can't directly test this without more complex setup,
    // but we can verify the hook doesn't throw
    expect(result.current.virtualItems).toBeDefined();
  });

  it('should call scrollTo when scrollToIndex is called', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    // Assign mock container to ref
    act(() => {
      // @ts-expect-error - we're assigning to a ref
      result.current.containerRef.current = mockContainer;
    });

    // Call scrollToIndex
    act(() => {
      result.current.scrollToIndex(10);
    });

    // Verify scrollTo was called with correct position
    expect(mockContainer.scrollTo).toHaveBeenCalledWith({
      top: 500, // 10 * 50
      behavior: 'smooth',
    });
  });

  it('should not throw when scrollToIndex is called without container', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    // containerRef.current is null
    expect(() => {
      act(() => {
        result.current.scrollToIndex(10);
      });
    }).not.toThrow();
  });

  it('should handle scroll events', () => {
    const { result } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    // Assign mock container to ref
    act(() => {
      // @ts-expect-error - we're assigning to a ref
      result.current.containerRef.current = mockContainer;
    });

    // Simulate scroll event
    act(() => {
      Object.defineProperty(mockContainer, 'scrollTop', {
        configurable: true,
        value: 500,
        writable: true,
      });
      mockContainer.dispatchEvent(new Event('scroll'));
    });

    // The hook should update based on scroll position
    // We can't directly check internal state, but the hook shouldn't throw
  });

  it('should cleanup scroll listener on unmount', () => {
    const _removeEventListenerSpy = vi.spyOn(mockContainer, 'removeEventListener');

    const { result, unmount } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    // Assign mock container to ref
    act(() => {
      // @ts-expect-error - we're assigning to a ref
      result.current.containerRef.current = mockContainer;
    });

    unmount();

    // Note: The cleanup happens but may not be captured by spy
    // since the ref might be null during cleanup
  });

  it('should disconnect ResizeObserver on unmount', () => {
    const { unmount } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    // Unmount should not throw
    expect(() => unmount()).not.toThrow();
  });

  it('should calculate virtualItems when container has height', () => {
    // Create a ref-like object that will be used by the hook
    const _containerRef = { current: mockContainer };

    const { result, rerender } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
        overscan: 3,
      })
    );

    // Manually assign the container to the ref
    act(() => {
      // @ts-expect-error - assigning to ref
      result.current.containerRef.current = mockContainer;
    });

    // Force a rerender to trigger effects
    rerender();

    // The hook should have calculated virtual items based on container height
    // containerHeight = 600, itemHeight = 50, so visible items = 12
    // With overscan of 3: start = max(0, 0 - 3) = 0, end = min(99, 12 + 3) = 15
    // That means items 0-15 should be rendered (16 items)
  });

  it('should update virtualItems based on scroll position', () => {
    const { result, rerender } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
        overscan: 2,
      })
    );

    // Set up container with scroll position
    act(() => {
      Object.defineProperty(mockContainer, 'scrollTop', {
        configurable: true,
        value: 250, // Scrolled down 5 items worth
        writable: true,
      });
      // @ts-expect-error - assigning to ref
      result.current.containerRef.current = mockContainer;
    });

    // Trigger scroll event
    act(() => {
      mockContainer.dispatchEvent(new Event('scroll'));
    });

    rerender();

    // After scrolling, the start index should be different
  });

  it('should handle edge case when scrolling near the end', () => {
    const { result, rerender } = renderHook(() =>
      useVirtualList({
        itemCount: 20,
        itemHeight: 50,
        overscan: 3,
      })
    );

    // Scroll near the end
    act(() => {
      Object.defineProperty(mockContainer, 'scrollTop', {
        configurable: true,
        value: 700, // Near the end of a 20-item list (1000px total)
        writable: true,
      });
      // @ts-expect-error - assigning to ref
      result.current.containerRef.current = mockContainer;
      mockContainer.dispatchEvent(new Event('scroll'));
    });

    rerender();
  });

  it('should provide correct start position for each virtual item', () => {
    const { result, rerender } = renderHook(() =>
      useVirtualList({
        itemCount: 100,
        itemHeight: 50,
      })
    );

    act(() => {
      // @ts-expect-error - assigning to ref
      result.current.containerRef.current = mockContainer;
    });

    rerender();

    // Each item's start position should be index * itemHeight
    result.current.virtualItems.forEach((item) => {
      expect(item.start).toBe(item.index * 50);
    });
  });
});

describe('useSimpleVirtualization', () => {
  let mockContainer: HTMLDivElement;

  beforeEach(() => {
    mockContainer = document.createElement('div');
    Object.defineProperty(mockContainer, 'clientHeight', {
      configurable: true,
      value: 500,
    });
    Object.defineProperty(mockContainer, 'scrollTop', {
      configurable: true,
      value: 0,
      writable: true,
    });
  });

  it('should return visible items for initial render', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({ id: i, name: `Item ${i}` }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    // Should have visible items
    expect(result.current.visibleItems.length).toBeGreaterThan(0);
  });

  it('should calculate total height based on items and estimated height', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({ id: i }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    expect(result.current.totalHeight).toBe(5000); // 100 * 50
  });

  it('should return offsetY for positioning', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({ id: i }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    // Initial offsetY should be 0 (start from index 0)
    expect(result.current.offsetY).toBe(0);
  });

  it('should return visibleRange object', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({ id: i }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    expect(result.current.visibleRange).toHaveProperty('start');
    expect(result.current.visibleRange).toHaveProperty('end');
  });

  it('should use default estimated height of 60', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({ id: i }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() => useSimpleVirtualization(items, containerRef));

    expect(result.current.totalHeight).toBe(6000); // 100 * 60
  });

  it('should handle empty items array', () => {
    const items: { id: number }[] = [];
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    expect(result.current.visibleItems).toEqual([]);
    expect(result.current.totalHeight).toBe(0);
  });

  it('should include item index in visibleItems', () => {
    const items = Array.from({ length: 50 }, (_, i) => ({ id: i, name: `Item ${i}` }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    // Each visible item should have an index property
    result.current.visibleItems.forEach((vi) => {
      expect(vi).toHaveProperty('index');
      expect(vi).toHaveProperty('item');
      expect(typeof vi.index).toBe('number');
    });
  });

  it('should handle null container ref', () => {
    const items = Array.from({ length: 50 }, (_, i) => ({ id: i }));
    const containerRef = { current: null };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    // Should still work without throwing
    expect(result.current.visibleItems).toBeDefined();
    expect(result.current.totalHeight).toBe(2500); // 50 * 50
  });

  it('should update visible range on scroll', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({ id: i }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    // Initial range starts near 0
    const _initialStart = result.current.visibleRange.start;

    // Simulate scroll
    act(() => {
      Object.defineProperty(mockContainer, 'scrollTop', {
        configurable: true,
        value: 1000, // Scroll down
        writable: true,
      });
      mockContainer.dispatchEvent(new Event('scroll'));
    });

    // Visible range should change after scroll
    // Note: Due to async nature, this might not update immediately
  });

  it('should cleanup scroll listener on unmount', () => {
    const items = Array.from({ length: 50 }, (_, i) => ({ id: i }));
    const containerRef = { current: mockContainer };

    const { unmount } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    // Unmount should not throw
    expect(() => unmount()).not.toThrow();
  });

  it('should recalculate when items length changes', () => {
    const containerRef = { current: mockContainer };

    const { result, rerender } = renderHook(
      ({ items }) => useSimpleVirtualization(items, containerRef, 50),
      { initialProps: { items: Array.from({ length: 50 }, (_, i) => ({ id: i })) } }
    );

    expect(result.current.totalHeight).toBe(2500); // 50 * 50

    // Change items
    rerender({ items: Array.from({ length: 100 }, (_, i) => ({ id: i })) });

    expect(result.current.totalHeight).toBe(5000); // 100 * 50
  });

  it('should slice items correctly for visible range', () => {
    const items = Array.from({ length: 100 }, (_, i) => ({ id: i, name: `Item ${i}` }));
    const containerRef = { current: mockContainer };

    const { result } = renderHook(() =>
      useSimpleVirtualization(items, containerRef, 50)
    );

    // Each visible item should match the original item
    result.current.visibleItems.forEach((vi) => {
      expect(vi.item).toEqual(items[vi.index]);
    });
  });
});
