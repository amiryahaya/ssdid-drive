import { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { open } from '@tauri-apps/plugin-dialog';
import { readTextFile } from '@tauri-apps/plugin-fs';
import { tauriService } from '@/services/tauri';
import { ArrowLeft, Upload, CheckCircle, AlertCircle, FileKey, Server } from 'lucide-react';

type RecoveryPath = null | 'two-files' | 'file-and-server';
type StepState = 'idle' | 'loading' | 'success' | 'error';

interface RecoveryFile {
  path: string;
  contents: string;
  share_index?: number;
  user_did?: string;
}

function parseRecoveryFile(contents: string): { share_index?: number; user_did?: string } {
  try {
    const parsed = JSON.parse(contents);
    return {
      share_index: parsed.share_index,
      user_did: parsed.user_did,
    };
  } catch {
    return {};
  }
}

export function RecoveryPage() {
  const navigate = useNavigate();
  const [path, setPath] = useState<RecoveryPath>(null);
  const [step, setStep] = useState<StepState>('idle');
  const [error, setError] = useState<string | null>(null);
  const [file1, setFile1] = useState<RecoveryFile | null>(null);
  const [file2, setFile2] = useState<RecoveryFile | null>(null);
  const [serverFile, setServerFile] = useState<RecoveryFile | null>(null);

  const handlePickFile = async (slot: 'file1' | 'file2' | 'serverFile') => {
    setError(null);
    try {
      const selected = await open({
        filters: [{ name: 'Recovery File', extensions: ['recovery'] }],
        multiple: false,
      });
      if (!selected) return;

      const filePath = selected as string;
      const contents = await readTextFile(filePath);
      const meta = parseRecoveryFile(contents);
      const recoveryFile: RecoveryFile = { path: filePath, contents, ...meta };

      if (slot === 'file1') {
        setFile1(recoveryFile);
      } else if (slot === 'file2') {
        setFile2(recoveryFile);
      } else {
        setServerFile(recoveryFile);
      }
    } catch (err) {
      setError(`Failed to read recovery file: ${err instanceof Error ? err.message : String(err)}`);
    }
  };

  const validateTwoFiles = (): string | null => {
    if (!file1 || !file2) return 'Please upload both recovery files.';
    if (file1.share_index !== undefined && file2.share_index !== undefined) {
      if (file1.share_index === file2.share_index) {
        return 'Both files have the same share index. Please upload two different recovery files.';
      }
    }
    if (
      file1.user_did &&
      file2.user_did &&
      file1.user_did !== file2.user_did
    ) {
      return 'Recovery files belong to different accounts. Please upload files from the same account.';
    }
    return null;
  };

  const handleRecoverWithFiles = async () => {
    const validationError = validateTwoFiles();
    if (validationError) {
      setError(validationError);
      return;
    }
    setStep('loading');
    setError(null);
    try {
      await tauriService.recoverWithFiles(file1!.contents, file2!.contents);
      setStep('success');
      setTimeout(() => navigate('/login'), 2500);
    } catch (err) {
      setStep('error');
      setError(`Recovery failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  };

  const handleRecoverWithFileAndServer = async () => {
    if (!serverFile) {
      setError('Please upload your recovery file.');
      return;
    }
    setStep('loading');
    setError(null);
    try {
      await tauriService.recoverWithFileAndServer(serverFile.contents);
      setStep('success');
      setTimeout(() => navigate('/login'), 2500);
    } catch (err) {
      setStep('error');
      setError(`Recovery failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  };

  const handleReset = () => {
    setPath(null);
    setStep('idle');
    setError(null);
    setFile1(null);
    setFile2(null);
    setServerFile(null);
  };

  if (step === 'success') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
        <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border text-center">
          <CheckCircle className="mx-auto h-16 w-16 text-green-500 mb-4" />
          <h2 className="text-2xl font-bold mb-2">Account Recovered</h2>
          <p className="text-muted-foreground text-sm">
            Your account has been successfully recovered. Redirecting to login…
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-primary/10 to-secondary/10">
      <div className="w-full max-w-md p-8 bg-card rounded-2xl shadow-xl border">
        {/* Header */}
        <div className="flex flex-col items-center mb-8">
          <img
            src="/app-icon.png"
            alt="SSDID Drive"
            className="h-20 w-20 rounded-2xl mb-4"
          />
          <h1 className="text-2xl font-bold">Recover Account</h1>
          <p className="text-muted-foreground text-sm mt-1 text-center">
            Restore access to your SSDID Drive account
          </p>
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 p-3 bg-destructive/10 text-destructive text-sm rounded-lg flex items-start gap-2">
            <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
            <span>{error}</span>
            <button
              onClick={() => setError(null)}
              className="ml-auto underline hover:no-underline shrink-0"
            >
              Dismiss
            </button>
          </div>
        )}

        {/* Path selection */}
        {path === null && (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground text-center mb-4">
              How would you like to recover your account?
            </p>
            <button
              onClick={() => setPath('two-files')}
              className="w-full p-4 rounded-xl border border-border bg-background hover:bg-accent hover:border-primary transition-colors text-left flex items-start gap-3"
            >
              <FileKey className="h-5 w-5 text-primary mt-0.5 shrink-0" />
              <div>
                <p className="font-medium text-sm">I have 2 recovery files</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Use two .recovery files saved from a previous backup.
                </p>
              </div>
            </button>
            <button
              onClick={() => setPath('file-and-server')}
              className="w-full p-4 rounded-xl border border-border bg-background hover:bg-accent hover:border-primary transition-colors text-left flex items-start gap-3"
            >
              <Server className="h-5 w-5 text-primary mt-0.5 shrink-0" />
              <div>
                <p className="font-medium text-sm">I have 1 recovery file + server share</p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Use one .recovery file combined with the server-held share.
                </p>
              </div>
            </button>
          </div>
        )}

        {/* Path A: Two files */}
        {path === 'two-files' && (
          <div className="space-y-4">
            <div className="space-y-3">
              <FileUploadSlot
                label="First recovery file"
                file={file1}
                onPick={() => handlePickFile('file1')}
                disabled={step === 'loading'}
              />
              <FileUploadSlot
                label="Second recovery file"
                file={file2}
                onPick={() => handlePickFile('file2')}
                disabled={step === 'loading'}
              />
            </div>

            <button
              onClick={handleRecoverWithFiles}
              disabled={!file1 || !file2 || step === 'loading'}
              className="w-full py-2.5 px-4 bg-primary text-primary-foreground rounded-lg font-medium text-sm hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {step === 'loading' ? 'Recovering…' : 'Recover Account'}
            </button>

            <button
              onClick={handleReset}
              disabled={step === 'loading'}
              className="w-full py-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              Choose a different recovery method
            </button>
          </div>
        )}

        {/* Path B: File + server */}
        {path === 'file-and-server' && (
          <div className="space-y-4">
            <div className="space-y-3">
              <FileUploadSlot
                label="Recovery file"
                file={serverFile}
                onPick={() => handlePickFile('serverFile')}
                disabled={step === 'loading'}
              />
              <p className="text-xs text-muted-foreground">
                The server will provide the second share automatically.
              </p>
            </div>

            <button
              onClick={handleRecoverWithFileAndServer}
              disabled={!serverFile || step === 'loading'}
              className="w-full py-2.5 px-4 bg-primary text-primary-foreground rounded-lg font-medium text-sm hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {step === 'loading' ? 'Recovering…' : 'Recover Account'}
            </button>

            <button
              onClick={handleReset}
              disabled={step === 'loading'}
              className="w-full py-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              Choose a different recovery method
            </button>
          </div>
        )}

        {/* Back to login */}
        <div className="mt-6 text-center">
          <Link
            to="/login"
            className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            <ArrowLeft className="h-3.5 w-3.5" />
            Back to login
          </Link>
        </div>
      </div>
    </div>
  );
}

interface FileUploadSlotProps {
  label: string;
  file: RecoveryFile | null;
  onPick: () => void;
  disabled: boolean;
}

function FileUploadSlot({ label, file, onPick, disabled }: FileUploadSlotProps) {
  const fileName = file?.path.split('/').pop() ?? file?.path.split('\\').pop();
  return (
    <div>
      <p className="text-xs font-medium text-muted-foreground mb-1.5">{label}</p>
      <button
        onClick={onPick}
        disabled={disabled}
        className={`w-full p-3 rounded-lg border-2 border-dashed transition-colors text-left flex items-center gap-3 disabled:cursor-not-allowed ${
          file
            ? 'border-primary/50 bg-primary/5 hover:border-primary'
            : 'border-border bg-background hover:border-primary/50 hover:bg-accent'
        }`}
      >
        <Upload className={`h-4 w-4 shrink-0 ${file ? 'text-primary' : 'text-muted-foreground'}`} />
        <span className={`text-sm truncate ${file ? 'text-foreground font-medium' : 'text-muted-foreground'}`}>
          {file ? fileName : 'Click to select .recovery file'}
        </span>
      </button>
    </div>
  );
}
