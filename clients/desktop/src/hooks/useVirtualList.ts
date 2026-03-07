import { useState, useEffect, useRef, useMemo, useCallback } from 'react';

interface VirtualListOptions {
  itemCount: number;
  itemHeight: number;
  overscan?: number;
}

interface VirtualListResult {
  virtualItems: { index: number; start: number }[];
  totalHeight: number;
  containerRef: React.RefObject<HTMLDivElement>;
  scrollToIndex: (index: number) => void;
}

/**
 * Hook for virtualizing long lists.
 * Only renders items that are visible in the viewport plus overscan.
 */
export function useVirtualList({
  itemCount,
  itemHeight,
  overscan = 3,
}: VirtualListOptions): VirtualListResult {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scrollTop, setScrollTop] = useState(0);
  const [containerHeight, setContainerHeight] = useState(0);

  // Update container height on mount and resize
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const updateHeight = () => {
      setContainerHeight(container.clientHeight);
    };

    updateHeight();

    const resizeObserver = new ResizeObserver(updateHeight);
    resizeObserver.observe(container);

    return () => resizeObserver.disconnect();
  }, []);

  // Handle scroll events
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const handleScroll = () => {
      setScrollTop(container.scrollTop);
    };

    container.addEventListener('scroll', handleScroll, { passive: true });
    return () => container.removeEventListener('scroll', handleScroll);
  }, []);

  // Calculate visible items
  const virtualItems = useMemo(() => {
    if (containerHeight === 0) return [];

    const startIndex = Math.max(0, Math.floor(scrollTop / itemHeight) - overscan);
    const endIndex = Math.min(
      itemCount - 1,
      Math.ceil((scrollTop + containerHeight) / itemHeight) + overscan
    );

    const items: { index: number; start: number }[] = [];
    for (let i = startIndex; i <= endIndex; i++) {
      items.push({
        index: i,
        start: i * itemHeight,
      });
    }

    return items;
  }, [scrollTop, containerHeight, itemCount, itemHeight, overscan]);

  const totalHeight = itemCount * itemHeight;

  const scrollToIndex = useCallback(
    (index: number) => {
      const container = containerRef.current;
      if (!container) return;

      const targetScrollTop = index * itemHeight;
      container.scrollTo({ top: targetScrollTop, behavior: 'smooth' });
    },
    [itemHeight]
  );

  return {
    virtualItems,
    totalHeight,
    containerRef,
    scrollToIndex,
  };
}

/**
 * Simplified hook for variable height items using measurement.
 * For complex cases, consider using @tanstack/react-virtual.
 */
export function useSimpleVirtualization<T>(
  items: T[],
  containerRef: React.RefObject<HTMLElement>,
  estimatedItemHeight: number = 60
) {
  const [visibleRange, setVisibleRange] = useState({ start: 0, end: 20 });

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const calculateVisibleRange = () => {
      const scrollTop = container.scrollTop;
      const containerHeight = container.clientHeight;
      const overscan = 5;

      const start = Math.max(0, Math.floor(scrollTop / estimatedItemHeight) - overscan);
      const end = Math.min(
        items.length,
        Math.ceil((scrollTop + containerHeight) / estimatedItemHeight) + overscan
      );

      setVisibleRange({ start, end });
    };

    calculateVisibleRange();

    container.addEventListener('scroll', calculateVisibleRange, { passive: true });
    return () => container.removeEventListener('scroll', calculateVisibleRange);
  }, [items.length, containerRef, estimatedItemHeight]);

  const visibleItems = useMemo(() => {
    return items.slice(visibleRange.start, visibleRange.end).map((item, i) => ({
      item,
      index: visibleRange.start + i,
    }));
  }, [items, visibleRange]);

  const totalHeight = items.length * estimatedItemHeight;
  const offsetY = visibleRange.start * estimatedItemHeight;

  return {
    visibleItems,
    totalHeight,
    offsetY,
    visibleRange,
  };
}
