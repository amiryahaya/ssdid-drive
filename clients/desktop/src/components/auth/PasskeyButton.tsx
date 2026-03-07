import { Loader2, KeyRound } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { Button } from '@/components/ui/Button';

interface PasskeyButtonProps {
  email?: string;
}

export function PasskeyButton({ email }: PasskeyButtonProps) {
  const navigate = useNavigate();
  const { loginWithPasskey, isLoading } = useAuthStore();

  const handlePasskeyLogin = async () => {
    try {
      await loginWithPasskey(email);
      navigate('/files');
    } catch (err) {
      console.error('Passkey login failed:', err);
    }
  };

  return (
    <Button
      type="button"
      variant="outline"
      className="w-full"
      disabled={isLoading}
      onClick={handlePasskeyLogin}
    >
      {isLoading ? (
        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
      ) : (
        <KeyRound className="mr-2 h-4 w-4" />
      )}
      Sign in with Passkey
    </Button>
  );
}
