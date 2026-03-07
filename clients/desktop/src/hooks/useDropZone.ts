import { useState, useCallback, DragEvent } from 'react';

interface UseDropZoneOptions {
  onDrop: (files: File[]) => void;
  disabled?: boolean;
}

interface UseDropZoneReturn {
  isDragOver: boolean;
  dropZoneProps: {
    onDragEnter: (e: DragEvent) => void;
    onDragLeave: (e: DragEvent) => void;
    onDragOver: (e: DragEvent) => void;
    onDrop: (e: DragEvent) => void;
  };
}

export function useDropZone({ onDrop, disabled = false }: UseDropZoneOptions): UseDropZoneReturn {
  const [isDragOver, setIsDragOver] = useState(false);
  const [_dragCounter, setDragCounter] = useState(0);

  const handleDragEnter = useCallback(
    (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();

      if (disabled) return;

      setDragCounter((prev) => prev + 1);
      if (e.dataTransfer?.items && e.dataTransfer.items.length > 0) {
        setIsDragOver(true);
      }
    },
    [disabled]
  );

  const handleDragLeave = useCallback(
    (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();

      if (disabled) return;

      setDragCounter((prev) => {
        const newCounter = prev - 1;
        if (newCounter === 0) {
          setIsDragOver(false);
        }
        return newCounter;
      });
    },
    [disabled]
  );

  const handleDragOver = useCallback(
    (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();

      if (disabled) return;

      // Set the drop effect
      if (e.dataTransfer) {
        e.dataTransfer.dropEffect = 'copy';
      }
    },
    [disabled]
  );

  const handleDrop = useCallback(
    (e: DragEvent) => {
      e.preventDefault();
      e.stopPropagation();

      setIsDragOver(false);
      setDragCounter(0);

      if (disabled) return;

      const files = e.dataTransfer?.files;
      if (files && files.length > 0) {
        const fileArray = Array.from(files);
        onDrop(fileArray);
      }
    },
    [disabled, onDrop]
  );

  return {
    isDragOver,
    dropZoneProps: {
      onDragEnter: handleDragEnter,
      onDragLeave: handleDragLeave,
      onDragOver: handleDragOver,
      onDrop: handleDrop,
    },
  };
}
