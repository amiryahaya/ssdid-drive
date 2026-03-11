import { Component, ReactNode } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { captureError, addBreadcrumb, type SeverityLevel } from '@/lib/sentry';

interface ErrorBoundaryProps {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: React.ErrorInfo) => void;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

/**
 * Error boundary component that catches JavaScript errors in child components.
 * Displays a fallback UI instead of crashing the entire app.
 */
export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo): void {
    if (import.meta.env.DEV) {
      console.error('ErrorBoundary caught an error:', error, errorInfo);
    }

    // Report to Sentry
    addBreadcrumb('error-boundary', 'Component error caught', 'error' as SeverityLevel, {
      componentStack: errorInfo.componentStack,
    });
    captureError(error, {
      componentStack: errorInfo.componentStack,
      boundary: 'ErrorBoundary',
    });

    this.props.onError?.(error, errorInfo);
  }

  handleRetry = (): void => {
    this.setState({ hasError: false, error: null });
  };

  render(): ReactNode {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div
          className="flex flex-col items-center justify-center min-h-[200px] p-8 text-center"
          role="alert"
        >
          <AlertTriangle className="h-12 w-12 text-destructive mb-4" />
          <h2 className="text-lg font-semibold mb-2">Something went wrong</h2>
          <p className="text-sm text-muted-foreground mb-4 max-w-md">
            An unexpected error occurred. Please try again or refresh the page.
          </p>
          {process.env.NODE_ENV === 'development' && this.state.error && (
            <pre className="text-xs text-left bg-muted p-4 rounded-md mb-4 max-w-full overflow-auto">
              {this.state.error.message}
            </pre>
          )}
          <Button onClick={this.handleRetry}>
            <RefreshCw className="h-4 w-4 mr-2" />
            Try Again
          </Button>
        </div>
      );
    }

    return this.props.children;
  }
}

interface PageErrorBoundaryProps {
  children: ReactNode;
}

/**
 * Error boundary specifically for page-level errors.
 * Shows a full-page error state with navigation options.
 */
export class PageErrorBoundary extends Component<
  PageErrorBoundaryProps,
  ErrorBoundaryState
> {
  constructor(props: PageErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo): void {
    if (import.meta.env.DEV) {
      console.error('PageErrorBoundary caught an error:', error, errorInfo);
    }

    // Report to Sentry
    addBreadcrumb('error-boundary', 'Page-level error caught', 'fatal' as SeverityLevel, {
      componentStack: errorInfo.componentStack,
    });
    captureError(error, {
      componentStack: errorInfo.componentStack,
      boundary: 'PageErrorBoundary',
    });
  }

  handleRefresh = (): void => {
    window.location.reload();
  };

  handleGoHome = (): void => {
    window.location.href = '/';
  };

  render(): ReactNode {
    if (this.state.hasError) {
      return (
        <div
          className="flex flex-col items-center justify-center min-h-screen p-8 text-center bg-background"
          role="alert"
        >
          <AlertTriangle className="h-16 w-16 text-destructive mb-6" />
          <h1 className="text-2xl font-bold mb-2">Oops! Something went wrong</h1>
          <p className="text-muted-foreground mb-6 max-w-md">
            We're sorry, but something unexpected happened. Please try refreshing the page
            or go back to the home page.
          </p>
          {process.env.NODE_ENV === 'development' && this.state.error && (
            <details className="text-left bg-muted p-4 rounded-md mb-6 max-w-2xl w-full">
              <summary className="cursor-pointer font-medium mb-2">
                Error Details (Development Only)
              </summary>
              <pre className="text-xs overflow-auto whitespace-pre-wrap">
                {this.state.error.stack}
              </pre>
            </details>
          )}
          <div className="flex gap-4">
            <Button variant="outline" onClick={this.handleGoHome}>
              Go to Home
            </Button>
            <Button onClick={this.handleRefresh}>
              <RefreshCw className="h-4 w-4 mr-2" />
              Refresh Page
            </Button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
