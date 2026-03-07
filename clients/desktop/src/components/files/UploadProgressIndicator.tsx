import { Upload, CheckCircle, AlertCircle, X } from 'lucide-react';
import { Progress } from '@/components/ui/progress';

type UploadPhase = 'preparing' | 'encrypting' | 'uploading' | 'confirming' | 'complete' | 'error';

interface UploadProgress {
  file_id: string;
  file_name: string;
  phase: UploadPhase;
  bytes_uploaded: number;
  total_bytes: number;
  progress_percent: number;
}

interface UploadProgressIndicatorProps {
  uploads: Map<string, UploadProgress>;
  onDismiss?: (uploadId: string) => void;
}

const phaseLabels: Record<UploadPhase, string> = {
  preparing: 'Preparing...',
  encrypting: 'Encrypting...',
  uploading: 'Uploading...',
  confirming: 'Finalizing...',
  complete: 'Complete',
  error: 'Failed',
};

function UploadItem({
  uploadId,
  upload,
  onDismiss,
}: {
  uploadId: string;
  upload: UploadProgress;
  onDismiss?: (uploadId: string) => void;
}) {
  const isComplete = upload.phase === 'complete';
  const isError = upload.phase === 'error';

  return (
    <div className="flex items-start gap-3 p-3 border-b last:border-b-0">
      <div className="flex-shrink-0 mt-0.5">
        {isComplete ? (
          <CheckCircle className="h-5 w-5 text-green-500" />
        ) : isError ? (
          <AlertCircle className="h-5 w-5 text-destructive" />
        ) : (
          <Upload className="h-5 w-5 text-primary animate-pulse" />
        )}
      </div>

      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate" title={upload.file_name}>
          {upload.file_name}
        </p>

        <div className="mt-1">
          <Progress value={upload.progress_percent} className="h-1.5" />
        </div>

        <div className="flex items-center justify-between mt-1">
          <span
            className={`text-xs ${
              isError ? 'text-destructive' : 'text-muted-foreground'
            }`}
          >
            {phaseLabels[upload.phase]}
          </span>
          <span className="text-xs text-muted-foreground">
            {Math.round(upload.progress_percent)}%
          </span>
        </div>
      </div>

      {(isComplete || isError) && onDismiss && (
        <button
          onClick={() => onDismiss(uploadId)}
          className="flex-shrink-0 p-1 hover:bg-muted rounded"
          aria-label="Dismiss"
        >
          <X className="h-4 w-4 text-muted-foreground" />
        </button>
      )}
    </div>
  );
}

export function UploadProgressIndicator({
  uploads,
  onDismiss,
}: UploadProgressIndicatorProps) {
  const uploadEntries = Array.from(uploads.entries());

  if (uploadEntries.length === 0) {
    return null;
  }

  const activeCount = uploadEntries.filter(
    ([, u]) => u.phase !== 'complete' && u.phase !== 'error'
  ).length;

  return (
    <div className="fixed bottom-4 right-4 z-50 w-80 bg-card border rounded-lg shadow-lg overflow-hidden">
      {/* Header */}
      <div className="px-3 py-2 bg-muted/50 border-b">
        <div className="flex items-center gap-2">
          <Upload className="h-4 w-4" />
          <span className="text-sm font-medium">
            {activeCount > 0
              ? `Uploading ${activeCount} file${activeCount > 1 ? 's' : ''}`
              : 'Uploads'}
          </span>
        </div>
      </div>

      {/* Upload list */}
      <div className="max-h-60 overflow-y-auto">
        {uploadEntries.map(([uploadId, upload]) => (
          <UploadItem
            key={uploadId}
            uploadId={uploadId}
            upload={upload}
            onDismiss={onDismiss}
          />
        ))}
      </div>
    </div>
  );
}
