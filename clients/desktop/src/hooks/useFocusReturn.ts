import { useEffect, useRef } from 'react';

/**
 * Hook that returns focus to the previously focused element when a component unmounts.
 * Useful for modals, dropdowns, and other overlays.
 */
export function useFocusReturn(isActive: boolean) {
  const previousFocusRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (isActive) {
      // Store the currently focused element
      previousFocusRef.current = document.activeElement as HTMLElement;
    }

    return () => {
      // Return focus when the component becomes inactive
      if (isActive && previousFocusRef.current && previousFocusRef.current.focus) {
        // Use a small timeout to ensure the element is still in the DOM
        setTimeout(() => {
          previousFocusRef.current?.focus();
        }, 0);
      }
    };
  }, [isActive]);
}

/**
 * Hook that manages focus within a container using arrow keys.
 * Useful for lists, menus, and other navigable components.
 */
export function useRovingFocus(
  containerRef: React.RefObject<HTMLElement>,
  itemSelector: string = '[role="option"], [role="menuitem"], button, a'
) {
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const handleKeyDown = (event: KeyboardEvent) => {
      const items = Array.from(
        container.querySelectorAll<HTMLElement>(itemSelector)
      ).filter((item) => !item.hasAttribute('disabled') && item.tabIndex !== -1);

      if (items.length === 0) return;

      const currentIndex = items.findIndex((item) => item === document.activeElement);

      let nextIndex: number | null = null;

      switch (event.key) {
        case 'ArrowDown':
        case 'ArrowRight':
          event.preventDefault();
          nextIndex = currentIndex < items.length - 1 ? currentIndex + 1 : 0;
          break;
        case 'ArrowUp':
        case 'ArrowLeft':
          event.preventDefault();
          nextIndex = currentIndex > 0 ? currentIndex - 1 : items.length - 1;
          break;
        case 'Home':
          event.preventDefault();
          nextIndex = 0;
          break;
        case 'End':
          event.preventDefault();
          nextIndex = items.length - 1;
          break;
      }

      if (nextIndex !== null) {
        items[nextIndex]?.focus();
      }
    };

    container.addEventListener('keydown', handleKeyDown);
    return () => container.removeEventListener('keydown', handleKeyDown);
  }, [containerRef, itemSelector]);
}
