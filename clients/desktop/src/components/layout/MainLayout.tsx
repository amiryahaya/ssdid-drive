import { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { Header } from './Header';
import { SkipLink } from '../common/SkipLink';
import { GlobalShortcuts } from '../common/GlobalShortcuts';
import { KeyboardShortcutsDialog } from '../common/KeyboardShortcutsDialog';
import { RecoveryBanner } from '../recovery/RecoveryBanner';

interface MainLayoutProps {
  children: ReactNode;
}

export function MainLayout({ children }: MainLayoutProps) {
  const navigate = useNavigate();

  return (
    <div className="flex h-screen bg-background">
      <SkipLink href="#main-content">Skip to main content</SkipLink>
      <GlobalShortcuts />
      <KeyboardShortcutsDialog />
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Header />
        <RecoveryBanner onSetupClick={() => navigate('/settings?tab=recovery')} />
        <main
          id="main-content"
          className="flex-1 overflow-auto p-6"
          tabIndex={-1}
          role="main"
        >
          {children}
        </main>
      </div>
    </div>
  );
}
