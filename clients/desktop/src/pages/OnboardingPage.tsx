import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Shield,
  Lock,
  Share2,
  Key,
  Upload,
  ChevronRight,
  ChevronLeft,
  Check,
  Sparkles,
  Users,
  FileCheck,
  ArrowRight,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { useOnboardingStore, type OnboardingStep } from '@/stores/onboardingStore';
import { useAuthStore } from '@/stores/authStore';
import { RecoverySetupDialog } from '@/components/recovery/RecoverySetupDialog';

// Step indicator component
function StepIndicator({ steps, currentStep }: { steps: OnboardingStep[]; currentStep: OnboardingStep }) {
  const currentIndex = steps.indexOf(currentStep);

  return (
    <div className="flex items-center justify-center gap-2">
      {steps.map((step, index) => (
        <div
          key={step}
          className={`h-2 rounded-full transition-all duration-300 ${
            index === currentIndex
              ? 'w-8 bg-primary'
              : index < currentIndex
              ? 'w-2 bg-primary/60'
              : 'w-2 bg-muted'
          }`}
        />
      ))}
    </div>
  );
}

// Welcome Step
function WelcomeStep({ onNext }: { onNext: () => void }) {
  const user = useAuthStore((state) => state.user);

  return (
    <div className="flex flex-col items-center text-center">
      <div className="h-20 w-20 rounded-2xl bg-primary flex items-center justify-center mb-6">
        <Sparkles className="h-12 w-12 text-primary-foreground" />
      </div>

      <h1 className="text-3xl font-bold mb-3">
        Welcome{user?.name ? `, ${user.name.split(' ')[0]}` : ''}!
      </h1>

      <p className="text-lg text-muted-foreground mb-8 max-w-md">
        Your account is ready. Let's take a quick tour to help you get the most out of SSDID Drive.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 w-full max-w-2xl mb-8">
        <div className="p-4 rounded-lg border bg-card">
          <Lock className="h-8 w-8 text-primary mb-3" />
          <h3 className="font-semibold mb-1">Encrypted Storage</h3>
          <p className="text-sm text-muted-foreground">
            Your files are encrypted before they leave your device
          </p>
        </div>
        <div className="p-4 rounded-lg border bg-card">
          <Share2 className="h-8 w-8 text-primary mb-3" />
          <h3 className="font-semibold mb-1">Secure Sharing</h3>
          <p className="text-sm text-muted-foreground">
            Share files safely with end-to-end encryption
          </p>
        </div>
        <div className="p-4 rounded-lg border bg-card">
          <Key className="h-8 w-8 text-primary mb-3" />
          <h3 className="font-semibold mb-1">Account Recovery</h3>
          <p className="text-sm text-muted-foreground">
            Never lose access with trusted contact recovery
          </p>
        </div>
      </div>

      <Button onClick={onNext} size="lg">
        Get Started
        <ChevronRight className="h-5 w-5 ml-2" />
      </Button>
    </div>
  );
}

// Security Step
function SecurityStep({ onNext, onPrev }: { onNext: () => void; onPrev: () => void }) {
  return (
    <div className="flex flex-col items-center text-center">
      <div className="h-20 w-20 rounded-2xl bg-green-500/10 flex items-center justify-center mb-6">
        <Shield className="h-12 w-12 text-green-500" />
      </div>

      <h1 className="text-3xl font-bold mb-3">Post-Quantum Security</h1>

      <p className="text-lg text-muted-foreground mb-8 max-w-md">
        SSDID Drive uses next-generation cryptography to protect your data against future quantum computer attacks.
      </p>

      <div className="space-y-4 w-full max-w-lg mb-8">
        <div className="flex items-start gap-4 p-4 rounded-lg border bg-card text-left">
          <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
            <Lock className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h3 className="font-semibold mb-1">Client-Side Encryption</h3>
            <p className="text-sm text-muted-foreground">
              Files are encrypted on your device before upload. Not even we can see your data.
            </p>
          </div>
        </div>

        <div className="flex items-start gap-4 p-4 rounded-lg border bg-card text-left">
          <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
            <FileCheck className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h3 className="font-semibold mb-1">Zero-Knowledge Architecture</h3>
            <p className="text-sm text-muted-foreground">
              Your encryption keys never leave your device. Only you control access to your files.
            </p>
          </div>
        </div>

        <div className="flex items-start gap-4 p-4 rounded-lg border bg-card text-left">
          <div className="h-10 w-10 rounded-lg bg-primary/10 flex items-center justify-center shrink-0">
            <Users className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h3 className="font-semibold mb-1">Secure Key Exchange</h3>
            <p className="text-sm text-muted-foreground">
              Share files securely using ML-KEM and KAZ-KEM hybrid encryption protocols.
            </p>
          </div>
        </div>
      </div>

      <div className="flex gap-3">
        <Button variant="outline" onClick={onPrev}>
          <ChevronLeft className="h-5 w-5 mr-2" />
          Back
        </Button>
        <Button onClick={onNext}>
          Continue
          <ChevronRight className="h-5 w-5 ml-2" />
        </Button>
      </div>
    </div>
  );
}

// Recovery Step
function RecoveryStep({
  onNext,
  onPrev,
  onSkip,
}: {
  onNext: () => void;
  onPrev: () => void;
  onSkip: () => void;
}) {
  const [showSetupDialog, setShowSetupDialog] = useState(false);

  const handleSetupComplete = () => {
    setShowSetupDialog(false);
    onNext();
  };

  return (
    <div className="flex flex-col items-center text-center">
      <div className="h-20 w-20 rounded-2xl bg-amber-500/10 flex items-center justify-center mb-6">
        <Key className="h-12 w-12 text-amber-500" />
      </div>

      <h1 className="text-3xl font-bold mb-3">Set Up Account Recovery</h1>

      <p className="text-lg text-muted-foreground mb-8 max-w-md">
        Protect yourself from losing access. Choose trusted contacts who can help you recover your account if needed.
      </p>

      <div className="w-full max-w-lg mb-8 p-6 rounded-lg border bg-card">
        <h3 className="font-semibold mb-4 text-left">How it works:</h3>
        <div className="space-y-4 text-left">
          <div className="flex items-start gap-3">
            <div className="h-6 w-6 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-medium shrink-0">
              1
            </div>
            <p className="text-sm text-muted-foreground">
              Select 3-5 trusted contacts from your organization
            </p>
          </div>
          <div className="flex items-start gap-3">
            <div className="h-6 w-6 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-medium shrink-0">
              2
            </div>
            <p className="text-sm text-muted-foreground">
              Your recovery key is split using cryptographic secret sharing
            </p>
          </div>
          <div className="flex items-start gap-3">
            <div className="h-6 w-6 rounded-full bg-primary text-primary-foreground flex items-center justify-center text-sm font-medium shrink-0">
              3
            </div>
            <p className="text-sm text-muted-foreground">
              If you lose access, a threshold of trustees can help you recover
            </p>
          </div>
        </div>
      </div>

      <div className="flex flex-col gap-3 w-full max-w-sm">
        <Button onClick={() => setShowSetupDialog(true)} size="lg">
          <Key className="h-5 w-5 mr-2" />
          Set Up Recovery Now
        </Button>
        <div className="flex gap-3">
          <Button variant="outline" onClick={onPrev} className="flex-1">
            <ChevronLeft className="h-5 w-5 mr-2" />
            Back
          </Button>
          <Button variant="ghost" onClick={onSkip} className="flex-1">
            Skip for Now
            <ChevronRight className="h-5 w-5 ml-2" />
          </Button>
        </div>
      </div>

      <RecoverySetupDialog
        open={showSetupDialog}
        onOpenChange={setShowSetupDialog}
        onComplete={handleSetupComplete}
      />
    </div>
  );
}

// Ready Step
function ReadyStep({ onComplete }: { onComplete: () => void }) {
  const navigate = useNavigate();

  const handleComplete = () => {
    onComplete();
    navigate('/files');
  };

  return (
    <div className="flex flex-col items-center text-center">
      <div className="h-20 w-20 rounded-2xl bg-primary flex items-center justify-center mb-6">
        <Check className="h-12 w-12 text-primary-foreground" />
      </div>

      <h1 className="text-3xl font-bold mb-3">You're All Set!</h1>

      <p className="text-lg text-muted-foreground mb-8 max-w-md">
        Your secure workspace is ready. Start by uploading your first file or exploring the app.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 w-full max-w-lg mb-8">
        <div
          className="p-6 rounded-lg border bg-card hover:border-primary/50 transition-colors cursor-pointer group"
          onClick={handleComplete}
        >
          <Upload className="h-10 w-10 text-primary mb-3" />
          <h3 className="font-semibold mb-1">Upload Files</h3>
          <p className="text-sm text-muted-foreground">
            Drag and drop or click to upload your first encrypted file
          </p>
          <ArrowRight className="h-5 w-5 text-primary mt-3 group-hover:translate-x-1 transition-transform" />
        </div>

        <div
          className="p-6 rounded-lg border bg-card hover:border-primary/50 transition-colors cursor-pointer group"
          onClick={handleComplete}
        >
          <Share2 className="h-10 w-10 text-primary mb-3" />
          <h3 className="font-semibold mb-1">Share Securely</h3>
          <p className="text-sm text-muted-foreground">
            Share files with colleagues using end-to-end encryption
          </p>
          <ArrowRight className="h-5 w-5 text-primary mt-3 group-hover:translate-x-1 transition-transform" />
        </div>
      </div>

      <Button onClick={handleComplete} size="lg">
        Go to My Files
        <ArrowRight className="h-5 w-5 ml-2" />
      </Button>
    </div>
  );
}

export function OnboardingPage() {
  const { currentStep, nextStep, prevStep, skipRecovery, completeOnboarding } =
    useOnboardingStore();

  const steps: OnboardingStep[] = ['welcome', 'security', 'recovery', 'ready'];

  return (
    <div className="min-h-screen flex flex-col bg-gradient-to-br from-primary/5 to-secondary/5">
      {/* Header with step indicator */}
      <div className="p-6">
        <div className="flex items-center justify-between max-w-4xl mx-auto">
          <div className="flex items-center gap-2">
            <Shield className="h-6 w-6 text-primary" />
            <span className="font-semibold">SSDID Drive</span>
          </div>
          <StepIndicator steps={steps} currentStep={currentStep} />
          <div className="w-24" /> {/* Spacer for centering */}
        </div>
      </div>

      {/* Main content */}
      <div className="flex-1 flex items-center justify-center p-6">
        <div className="w-full max-w-4xl">
          {currentStep === 'welcome' && <WelcomeStep onNext={nextStep} />}
          {currentStep === 'security' && <SecurityStep onNext={nextStep} onPrev={prevStep} />}
          {currentStep === 'recovery' && (
            <RecoveryStep onNext={nextStep} onPrev={prevStep} onSkip={skipRecovery} />
          )}
          {currentStep === 'ready' && <ReadyStep onComplete={completeOnboarding} />}
        </div>
      </div>
    </div>
  );
}
