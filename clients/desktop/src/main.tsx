import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { LiveRegionProvider } from './components/common/LiveRegion';
import { PageErrorBoundary } from './components/common/ErrorBoundary';
import { initSentry } from './lib/sentry';
import App from './App';
import './index.css';

// Initialize Sentry error tracking as early as possible
initSentry().catch(() => {});

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      retry: 1,
    },
  },
});

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <PageErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <LiveRegionProvider>
            <App />
          </LiveRegionProvider>
        </BrowserRouter>
      </QueryClientProvider>
    </PageErrorBoundary>
  </React.StrictMode>
);
