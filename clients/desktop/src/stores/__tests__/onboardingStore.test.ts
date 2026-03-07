import { describe, it, expect, beforeEach } from 'vitest';
import { useOnboardingStore } from '../onboardingStore';

describe('onboardingStore', () => {
  beforeEach(() => {
    useOnboardingStore.setState({
      hasCompletedOnboarding: false,
      currentStep: 'welcome',
      skippedRecovery: false,
    });
  });

  describe('initial state', () => {
    it('should start on welcome step', () => {
      expect(useOnboardingStore.getState().currentStep).toBe('welcome');
    });

    it('should not have completed onboarding', () => {
      expect(useOnboardingStore.getState().hasCompletedOnboarding).toBe(false);
    });

    it('should not have skipped recovery', () => {
      expect(useOnboardingStore.getState().skippedRecovery).toBe(false);
    });
  });

  describe('setStep', () => {
    it('should set a specific step', () => {
      useOnboardingStore.getState().setStep('security');
      expect(useOnboardingStore.getState().currentStep).toBe('security');
    });
  });

  describe('nextStep', () => {
    it('should advance from welcome to security', () => {
      useOnboardingStore.getState().nextStep();
      expect(useOnboardingStore.getState().currentStep).toBe('security');
    });

    it('should advance from security to recovery', () => {
      useOnboardingStore.getState().setStep('security');
      useOnboardingStore.getState().nextStep();
      expect(useOnboardingStore.getState().currentStep).toBe('recovery');
    });

    it('should advance from recovery to ready', () => {
      useOnboardingStore.getState().setStep('recovery');
      useOnboardingStore.getState().nextStep();
      expect(useOnboardingStore.getState().currentStep).toBe('ready');
    });
  });

  describe('prevStep', () => {
    it('should go back from security to welcome', () => {
      useOnboardingStore.getState().setStep('security');
      useOnboardingStore.getState().prevStep();
      expect(useOnboardingStore.getState().currentStep).toBe('welcome');
    });

    it('should stay on welcome if already on welcome', () => {
      useOnboardingStore.getState().prevStep();
      expect(useOnboardingStore.getState().currentStep).toBe('welcome');
    });
  });

  describe('skipRecovery', () => {
    it('should set skippedRecovery to true', () => {
      useOnboardingStore.getState().skipRecovery();
      expect(useOnboardingStore.getState().skippedRecovery).toBe(true);
    });

    it('should advance past recovery step', () => {
      useOnboardingStore.getState().setStep('recovery');
      useOnboardingStore.getState().skipRecovery();
      expect(useOnboardingStore.getState().currentStep).toBe('ready');
    });
  });

  describe('completeOnboarding', () => {
    it('should mark onboarding as completed', () => {
      useOnboardingStore.getState().completeOnboarding();
      expect(useOnboardingStore.getState().hasCompletedOnboarding).toBe(true);
    });
  });

  describe('resetOnboarding', () => {
    it('should reset to initial state', () => {
      useOnboardingStore.getState().completeOnboarding();
      useOnboardingStore.getState().setStep('ready');
      useOnboardingStore.getState().resetOnboarding();

      const state = useOnboardingStore.getState();
      expect(state.hasCompletedOnboarding).toBe(false);
      expect(state.currentStep).toBe('welcome');
      expect(state.skippedRecovery).toBe(false);
    });
  });
});
