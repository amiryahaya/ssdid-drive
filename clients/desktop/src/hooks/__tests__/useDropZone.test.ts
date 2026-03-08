import { describe, it, expect, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useDropZone } from '../useDropZone';

// Mock DragEvent
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function createMockDragEvent(type: string, files: File[] = []): any {
  const dataTransfer = {
    items: files,
    files: { length: files.length, item: (i: number) => files[i] },
    dropEffect: 'none',
  };

  return {
    type,
    preventDefault: vi.fn(),
    stopPropagation: vi.fn(),
    dataTransfer,
  };
}

function createMockFile(name: string): File {
  return new File(['content'], name, { type: 'text/plain' });
}

describe('useDropZone', () => {
  it('should initialize with isDragOver as false', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    expect(result.current.isDragOver).toBe(false);
  });

  it('should set isDragOver to true on drag enter', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const event = createMockDragEvent('dragenter', [createMockFile('test.txt')]);

    act(() => {
      result.current.dropZoneProps.onDragEnter(event);
    });

    expect(result.current.isDragOver).toBe(true);
    expect(event.preventDefault).toHaveBeenCalled();
    expect(event.stopPropagation).toHaveBeenCalled();
  });

  it('should set isDragOver to false on drag leave when counter reaches 0', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const enterEvent = createMockDragEvent('dragenter', [createMockFile('test.txt')]);
    const leaveEvent = createMockDragEvent('dragleave');

    act(() => {
      result.current.dropZoneProps.onDragEnter(enterEvent);
    });

    expect(result.current.isDragOver).toBe(true);

    act(() => {
      result.current.dropZoneProps.onDragLeave(leaveEvent);
    });

    expect(result.current.isDragOver).toBe(false);
  });

  it('should handle multiple drag enter/leave events correctly', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const enterEvent1 = createMockDragEvent('dragenter', [createMockFile('test.txt')]);
    const enterEvent2 = createMockDragEvent('dragenter', [createMockFile('test.txt')]);
    const leaveEvent = createMockDragEvent('dragleave');

    // Enter twice (nested elements)
    act(() => {
      result.current.dropZoneProps.onDragEnter(enterEvent1);
      result.current.dropZoneProps.onDragEnter(enterEvent2);
    });

    expect(result.current.isDragOver).toBe(true);

    // Leave once - should still be true
    act(() => {
      result.current.dropZoneProps.onDragLeave(leaveEvent);
    });

    expect(result.current.isDragOver).toBe(true);

    // Leave again - now should be false
    act(() => {
      result.current.dropZoneProps.onDragLeave(leaveEvent);
    });

    expect(result.current.isDragOver).toBe(false);
  });

  it('should prevent default on drag over', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const event = createMockDragEvent('dragover');

    act(() => {
      result.current.dropZoneProps.onDragOver(event);
    });

    expect(event.preventDefault).toHaveBeenCalled();
    expect(event.stopPropagation).toHaveBeenCalled();
  });

  it('should set drop effect to copy on drag over', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const event = createMockDragEvent('dragover');

    act(() => {
      result.current.dropZoneProps.onDragOver(event);
    });

    expect(event.dataTransfer.dropEffect).toBe('copy');
  });

  it('should call onDrop with files on drop', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const files = [createMockFile('file1.txt'), createMockFile('file2.txt')];
    const event = {
      ...createMockDragEvent('drop'),
      dataTransfer: {
        files,
      },
    };

    act(() => {
      result.current.dropZoneProps.onDrop(event);
    });

    expect(onDrop).toHaveBeenCalledWith(files);
  });

  it('should reset isDragOver on drop', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const enterEvent = createMockDragEvent('dragenter', [createMockFile('test.txt')]);
    const dropEvent = {
      ...createMockDragEvent('drop'),
      dataTransfer: {
        files: [createMockFile('test.txt')],
      },
    };

    act(() => {
      result.current.dropZoneProps.onDragEnter(enterEvent);
    });

    expect(result.current.isDragOver).toBe(true);

    act(() => {
      result.current.dropZoneProps.onDrop(dropEvent);
    });

    expect(result.current.isDragOver).toBe(false);
  });

  it('should not respond to events when disabled', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop, disabled: true }));

    const enterEvent = createMockDragEvent('dragenter', [createMockFile('test.txt')]);
    const dropEvent = {
      ...createMockDragEvent('drop'),
      dataTransfer: {
        files: [createMockFile('test.txt')],
      },
    };

    act(() => {
      result.current.dropZoneProps.onDragEnter(enterEvent);
    });

    expect(result.current.isDragOver).toBe(false);

    act(() => {
      result.current.dropZoneProps.onDrop(dropEvent);
    });

    expect(onDrop).not.toHaveBeenCalled();
  });

  it('should not call onDrop when no files are dropped', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    const event = {
      ...createMockDragEvent('drop'),
      dataTransfer: {
        files: [],
      },
    };

    act(() => {
      result.current.dropZoneProps.onDrop(event);
    });

    expect(onDrop).not.toHaveBeenCalled();
  });

  it('should provide all required props', () => {
    const onDrop = vi.fn();
    const { result } = renderHook(() => useDropZone({ onDrop }));

    expect(result.current.dropZoneProps).toHaveProperty('onDragEnter');
    expect(result.current.dropZoneProps).toHaveProperty('onDragLeave');
    expect(result.current.dropZoneProps).toHaveProperty('onDragOver');
    expect(result.current.dropZoneProps).toHaveProperty('onDrop');
    expect(typeof result.current.dropZoneProps.onDragEnter).toBe('function');
    expect(typeof result.current.dropZoneProps.onDragLeave).toBe('function');
    expect(typeof result.current.dropZoneProps.onDragOver).toBe('function');
    expect(typeof result.current.dropZoneProps.onDrop).toBe('function');
  });
});
