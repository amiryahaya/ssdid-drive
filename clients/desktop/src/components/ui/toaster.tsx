import {
  Toast,
  ToastClose,
  ToastDescription,
  ToastProvider,
  ToastTitle,
  ToastViewport,
} from './toast';
import { useToastStore } from '../../stores/toastStore';
import type { ToastType } from '../../types';

const variantMap: Record<ToastType, 'success' | 'error' | 'warning' | 'info'> = {
  success: 'success',
  error: 'error',
  warning: 'warning',
  info: 'info',
};

export function Toaster() {
  const { toasts } = useToastStore();

  return (
    <ToastProvider>
      {toasts.map((toast) => (
        <Toast key={toast.id} variant={variantMap[toast.type]}>
          <div className="grid gap-1">
            <ToastTitle>{toast.title}</ToastTitle>
            {toast.description && (
              <ToastDescription>{toast.description}</ToastDescription>
            )}
          </div>
          <ToastClose />
        </Toast>
      ))}
      <ToastViewport />
    </ToastProvider>
  );
}
