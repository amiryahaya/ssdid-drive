import { useEffect } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { useSettingsStore } from '@/stores/settingsStore';
import { useOnboardingStore } from '@/stores/onboardingStore';
import { useNotificationStore } from '@/stores/notificationStore';
import { useDeepLink } from '@/hooks/useDeepLink';
import { MainLayout } from '@/components/layout/MainLayout';
import { LoginPage } from '@/pages/LoginPage';
import { RegisterPage } from '@/pages/RegisterPage';
import { OnboardingPage } from '@/pages/OnboardingPage';
import { FilesPage } from '@/pages/FilesPage';
import { FavoritesPage } from '@/pages/FavoritesPage';
import { SharedWithMePage } from '@/pages/SharedWithMePage';
import { MySharesPage } from '@/pages/MySharesPage';
import { PiiChatPage } from '@/pages/PiiChatPage';
import { ActivityPage } from '@/pages/ActivityPage';
import { SettingsPage } from '@/pages/SettingsPage';
import { InvitationsPage } from '@/pages/InvitationsPage';
import { MembersPage } from '@/pages/MembersPage';
import { JoinTenantPage } from '@/pages/JoinTenantPage';
import { RecoveryPage } from '@/pages/RecoveryPage';
import { EmailLoginPage } from '@/pages/EmailLoginPage';
import { TotpSetupPage } from '@/pages/TotpSetupPage';
import { UnlockScreen } from '@/components/auth/UnlockScreen';
import { Toaster } from '@/components/ui/toaster';
import { OfflineBanner } from '@/components/common/OfflineBanner';
import { ErrorBoundary } from '@/components/common/ErrorBoundary';
import { AutoLockProvider } from '@/components/common/AutoLockProvider';
import { TrayProvider } from '@/components/common/TrayProvider';

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const isLocked = useAuthStore((state) => state.isLocked);
  const hasCompletedOnboarding = useOnboardingStore((state) => state.hasCompletedOnboarding);

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  if (isLocked) {
    return <UnlockScreen />;
  }

  if (!hasCompletedOnboarding) {
    return <Navigate to="/onboarding" replace />;
  }

  return <>{children}</>;
}

function OnboardingRoute({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const isLocked = useAuthStore((state) => state.isLocked);
  const hasCompletedOnboarding = useOnboardingStore((state) => state.hasCompletedOnboarding);

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  if (isLocked) {
    return <UnlockScreen />;
  }

  if (hasCompletedOnboarding) {
    return <Navigate to="/files" replace />;
  }

  return <>{children}</>;
}

function PublicRoute({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const isLocked = useAuthStore((state) => state.isLocked);

  // If authenticated and not locked, redirect to files
  if (isAuthenticated && !isLocked) {
    return <Navigate to="/files" replace />;
  }

  return <>{children}</>;
}

function JoinTenantRoute() {
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const isLocked = useAuthStore((state) => state.isLocked);

  if (isAuthenticated && !isLocked) {
    return (
      <MainLayout>
        <JoinTenantPage />
      </MainLayout>
    );
  }

  return <JoinTenantPage />;
}

function App() {
  const checkAuth = useAuthStore((state) => state.checkAuth);
  const isAuthenticated = useAuthStore((state) => state.isAuthenticated);
  const applyTheme = useSettingsStore((state) => state.applyTheme);
  const startPolling = useNotificationStore((state) => state.startPolling);
  const stopPolling = useNotificationStore((state) => state.stopPolling);

  // Initialize deep link handling
  useDeepLink();

  useEffect(() => {
    checkAuth();
    applyTheme();
  }, [checkAuth, applyTheme]);

  // Poll for notifications when authenticated
  useEffect(() => {
    if (isAuthenticated) {
      startPolling();
    } else {
      stopPolling();
    }
    return () => stopPolling();
  }, [isAuthenticated, startPolling, stopPolling]);

  return (
    <>
      <AutoLockProvider />
      <OfflineBanner />
      <Routes>
        <Route
          path="/login"
          element={
            <PublicRoute>
              <LoginPage />
            </PublicRoute>
          }
        />
        <Route
          path="/login/email"
          element={
            <PublicRoute>
              <EmailLoginPage />
            </PublicRoute>
          }
        />
        <Route
          path="/login/totp-setup"
          element={<TotpSetupPage />}
        />
        <Route
          path="/register"
          element={
            <PublicRoute>
              <RegisterPage />
            </PublicRoute>
          }
        />
        <Route
          path="/recover"
          element={<RecoveryPage />}
        />
        <Route
          path="/join"
          element={<JoinTenantRoute />}
        />
        <Route
          path="/onboarding"
          element={
            <OnboardingRoute>
              <OnboardingPage />
            </OnboardingRoute>
          }
        />
        <Route
          path="/*"
          element={
            <ProtectedRoute>
              <TrayProvider />
              <MainLayout>
                <ErrorBoundary>
                  <Routes>
                    <Route path="/" element={<Navigate to="/files" replace />} />
                    <Route path="/files" element={<FilesPage />} />
                    <Route path="/files/:folderId" element={<FilesPage />} />
                    <Route path="/activity" element={<ActivityPage />} />
                    <Route path="/favorites" element={<FavoritesPage />} />
                    <Route path="/shared-with-me" element={<SharedWithMePage />} />
                    <Route path="/my-shares" element={<MySharesPage />} />
                    <Route path="/pii-chat" element={<PiiChatPage />} />
                    <Route path="/invitations" element={<InvitationsPage />} />
                    <Route path="/members" element={<MembersPage />} />
                    <Route path="/settings" element={<SettingsPage />} />
                  </Routes>
                </ErrorBoundary>
              </MainLayout>
            </ProtectedRoute>
          }
        />
      </Routes>
      <Toaster />
    </>
  );
}

export default App;
