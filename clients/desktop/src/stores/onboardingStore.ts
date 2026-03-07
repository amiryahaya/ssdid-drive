import { create } from 'zustand';
import { persist } from 'zustand/middleware';

export type OnboardingStep = 'welcome' | 'security' | 'recovery' | 'ready';

interface OnboardingState {
  hasCompletedOnboarding: boolean;
  currentStep: OnboardingStep;
  skippedRecovery: boolean;

  // Actions
  setStep: (step: OnboardingStep) => void;
  nextStep: () => void;
  prevStep: () => void;
  skipRecovery: () => void;
  completeOnboarding: () => void;
  resetOnboarding: () => void;
}

const STEPS: OnboardingStep[] = ['welcome', 'security', 'recovery', 'ready'];

export const useOnboardingStore = create<OnboardingState>()(
  persist(
    (set, get) => ({
      hasCompletedOnboarding: false,
      currentStep: 'welcome',
      skippedRecovery: false,

      setStep: (step) => set({ currentStep: step }),

      nextStep: () => {
        const currentIndex = STEPS.indexOf(get().currentStep);
        if (currentIndex < STEPS.length - 1) {
          set({ currentStep: STEPS[currentIndex + 1] });
        }
      },

      prevStep: () => {
        const currentIndex = STEPS.indexOf(get().currentStep);
        if (currentIndex > 0) {
          set({ currentStep: STEPS[currentIndex - 1] });
        }
      },

      skipRecovery: () => {
        set({ skippedRecovery: true });
        get().nextStep();
      },

      completeOnboarding: () => {
        set({ hasCompletedOnboarding: true, currentStep: 'welcome' });
      },

      resetOnboarding: () => {
        set({
          hasCompletedOnboarding: false,
          currentStep: 'welcome',
          skippedRecovery: false,
        });
      },
    }),
    {
      name: 'onboarding-storage',
    }
  )
);
