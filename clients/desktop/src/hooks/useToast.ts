import { useToastStore } from '../stores/toastStore';
import type { ToastType } from '../types';

interface ToastOptions {
  title: string;
  description?: string;
  duration?: number;
}

export function useToast() {
  const { addToast, removeToast, clearToasts, toasts } = useToastStore();

  const toast = (type: ToastType, options: ToastOptions) => {
    addToast({ type, ...options });
  };

  return {
    toasts,
    toast,
    success: (options: ToastOptions) => toast('success', options),
    error: (options: ToastOptions) => toast('error', options),
    info: (options: ToastOptions) => toast('info', options),
    warning: (options: ToastOptions) => toast('warning', options),
    dismiss: removeToast,
    dismissAll: clearToasts,
  };
}
