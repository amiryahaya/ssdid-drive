import { describe, it, expect, vi } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { MainLayout } from '../MainLayout';

// Mock child components to simplify tests
vi.mock('../Sidebar', () => ({
  Sidebar: () => <aside data-testid="sidebar">Sidebar</aside>,
}));

vi.mock('../Header', () => ({
  Header: () => <header data-testid="header">Header</header>,
}));

vi.mock('../../common/SkipLink', () => ({
  SkipLink: ({ children, href }: { children: React.ReactNode; href: string }) => (
    <a href={href} data-testid="skip-link">
      {children}
    </a>
  ),
}));

describe('MainLayout', () => {
  describe('structure', () => {
    it('should render sidebar', () => {
      render(<MainLayout>Content</MainLayout>);
      expect(screen.getByTestId('sidebar')).toBeInTheDocument();
    });

    it('should render header', () => {
      render(<MainLayout>Content</MainLayout>);
      expect(screen.getByTestId('header')).toBeInTheDocument();
    });

    it('should render children in main content area', () => {
      render(<MainLayout>Test Content</MainLayout>);
      expect(screen.getByText('Test Content')).toBeInTheDocument();
    });

    it('should render skip link for accessibility', () => {
      render(<MainLayout>Content</MainLayout>);
      const skipLink = screen.getByTestId('skip-link');
      expect(skipLink).toBeInTheDocument();
      expect(skipLink).toHaveAttribute('href', '#main-content');
    });
  });

  describe('accessibility', () => {
    it('should have main content with correct id', () => {
      render(<MainLayout>Content</MainLayout>);
      const main = screen.getByRole('main');
      expect(main).toHaveAttribute('id', 'main-content');
    });

    it('should have main role on content area', () => {
      render(<MainLayout>Content</MainLayout>);
      expect(screen.getByRole('main')).toBeInTheDocument();
    });

    it('should have tabIndex for focus management', () => {
      render(<MainLayout>Content</MainLayout>);
      const main = screen.getByRole('main');
      expect(main).toHaveAttribute('tabIndex', '-1');
    });
  });

  describe('layout structure', () => {
    it('should contain children within main element', () => {
      render(
        <MainLayout>
          <div data-testid="child-content">Child Content</div>
        </MainLayout>
      );
      const main = screen.getByRole('main');
      const child = screen.getByTestId('child-content');
      expect(main).toContainElement(child);
    });

    it('should render multiple children', () => {
      render(
        <MainLayout>
          <div data-testid="child-1">First</div>
          <div data-testid="child-2">Second</div>
        </MainLayout>
      );
      expect(screen.getByTestId('child-1')).toBeInTheDocument();
      expect(screen.getByTestId('child-2')).toBeInTheDocument();
    });
  });
});
