import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import { render } from '../../test/utils';
import { OnboardingPage } from '../OnboardingPage';
import { useOnboardingStore } from '../../stores/onboardingStore';
import { useAuthStore } from '../../stores/authStore';

vi.mock('../../components/recovery/RecoverySetupDialog', () => ({
  RecoverySetupDialog: ({ open, onClose }: { open: boolean; onClose: () => void }) =>
    open ? (
      <div data-testid="recovery-dialog">
        <button onClick={onClose}>Close</button>
      </div>
    ) : null,
}));

describe('OnboardingPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    useOnboardingStore.setState({
      hasCompletedOnboarding: false,
      currentStep: 'welcome',
      skippedRecovery: false,
    });
    useAuthStore.setState({
      user: { id: 'user-1', email: 'test@example.com', display_name: 'Test User' },
    });
  });

  describe('welcome step', () => {
    it('should show welcome content', () => {
      render(<OnboardingPage />);
      expect(screen.getByText(/welcome/i)).toBeInTheDocument();
    });

    it('should have a get started button', () => {
      render(<OnboardingPage />);
      expect(screen.getByText(/get started/i)).toBeInTheDocument();
    });

    it('should advance to security step on get started click', () => {
      render(<OnboardingPage />);
      fireEvent.click(screen.getByText(/get started/i));
      expect(useOnboardingStore.getState().currentStep).toBe('security');
    });
  });

  describe('security step', () => {
    beforeEach(() => {
      useOnboardingStore.setState({ currentStep: 'security' });
    });

    it('should show continue button', () => {
      render(<OnboardingPage />);
      expect(screen.getByText(/continue/i)).toBeInTheDocument();
    });

    it('should show back button', () => {
      render(<OnboardingPage />);
      expect(screen.getByText(/back/i)).toBeInTheDocument();
    });
  });

  describe('recovery step', () => {
    beforeEach(() => {
      useOnboardingStore.setState({ currentStep: 'recovery' });
    });

    it('should show recovery content', () => {
      render(<OnboardingPage />);
      expect(screen.getAllByText(/recovery/i).length).toBeGreaterThan(0);
    });

    it('should have a skip option', () => {
      render(<OnboardingPage />);
      expect(screen.getByText(/skip/i)).toBeInTheDocument();
    });
  });

  describe('ready step', () => {
    beforeEach(() => {
      useOnboardingStore.setState({ currentStep: 'ready' });
    });

    it('should show files-related content', () => {
      render(<OnboardingPage />);
      expect(screen.getAllByText(/files/i).length).toBeGreaterThan(0);
    });
  });
});
