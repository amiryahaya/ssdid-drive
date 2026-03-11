import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';

// Mock Tauri APIs
vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(),
}));

vi.mock('@tauri-apps/api/event', () => ({
  listen: vi.fn().mockResolvedValue(() => {}),
  emit: vi.fn(),
}));

vi.mock('@tauri-apps/plugin-dialog', () => ({
  open: vi.fn(),
  save: vi.fn(),
}));

// Mock window.matchMedia for Radix UI components
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

// Mock ResizeObserver for Radix UI
class ResizeObserverMock {
  observe() {}
  unobserve() {}
  disconnect() {}
}

window.ResizeObserver = ResizeObserverMock;

// Mock scrollIntoView
Element.prototype.scrollIntoView = vi.fn();

// Mock EventSource (not available in jsdom)
class EventSourceMock {
  static lastUrl: string = '';
  addEventListener = vi.fn();
  removeEventListener = vi.fn();
  close = vi.fn();
  onerror: ((event: Event) => void) | null = null;

  constructor(url: string) {
    EventSourceMock.lastUrl = url;
  }
}

window.EventSource = EventSourceMock as unknown as typeof EventSource;

// Mock HTMLElement.prototype.hasPointerCapture
HTMLElement.prototype.hasPointerCapture = vi.fn().mockReturnValue(false);
HTMLElement.prototype.setPointerCapture = vi.fn();
HTMLElement.prototype.releasePointerCapture = vi.fn();

// Mock global.fetch if not already mocked (individual tests may override)
if (!vi.isMockFunction(global.fetch)) {
  global.fetch = vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: () => Promise.resolve({}),
  });
}
