import { ReactNode } from 'react';
import { Sidebar } from './Sidebar';
import { Header } from './Header';
import { SkipLink } from '../common/SkipLink';
import { GlobalShortcuts } from '../common/GlobalShortcuts';
import { KeyboardShortcutsDialog } from '../common/KeyboardShortcutsDialog';

interface MainLayoutProps {
  children: ReactNode;
}

export function MainLayout({ children }: MainLayoutProps) {
  return (
    <div className="flex h-screen bg-background">
      <SkipLink href="#main-content">Skip to main content</SkipLink>
      <GlobalShortcuts />
      <KeyboardShortcutsDialog />
      <Sidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <Header />
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
