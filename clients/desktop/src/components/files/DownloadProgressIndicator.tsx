import { Download, CheckCircle, AlertCircle, X } from 'lucide-react';
import { Progress } from '@/components/ui/progress';

type DownloadPhase = 'preparing' | 'downloading' | 'decrypting' | 'writing' | 'complete' | 'error';

interface DownloadProgress {
  file_id: string;
  file_name: string;
  phase: DownloadPhase;
  bytes_downloaded: number;
  total_bytes: number;
  progress_percent: number;
}

interface DownloadProgressIndicatorProps {
  downloads: Map<string, DownloadProgress>;
  onDismiss?: (downloadId: string) => void;
}

const phaseLabels: Record<DownloadPhase, string> = {
  preparing: 'Preparing...',
  downloading: 'Downloading...',
  decrypting: 'Decrypting...',
  writing: 'Writing...',
  complete: 'Complete',
  error: 'Failed',
};

function DownloadItem({
  downloadId,
  download,
  onDismiss,
}: {
  downloadId: string;
  download: DownloadProgress;
  onDismiss?: (downloadId: string) => void;
}) {
  const isComplete = download.phase === 'complete';
  const isError = download.phase === 'error';

  return (
    <div className="flex items-start gap-3 p-3 border-b last:border-b-0">
      <div className="flex-shrink-0 mt-0.5">
        {isComplete ? (
          <CheckCircle className="h-5 w-5 text-green-500" />
        ) : isError ? (
          <AlertCircle className="h-5 w-5 text-destructive" />
        ) : (
          <Download className="h-5 w-5 text-primary animate-pulse" />
        )}
      </div>

      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate" title={download.file_name}>
          {download.file_name}
        </p>

        <div className="mt-1">
          <Progress value={download.progress_percent} className="h-1.5" />
        </div>

        <div className="flex items-center justify-between mt-1">
          <span
            className={`text-xs ${
              isError ? 'text-destructive' : 'text-muted-foreground'
            }`}
          >
            {phaseLabels[download.phase]}
          </span>
          <span className="text-xs text-muted-foreground">
            {Math.round(download.progress_percent)}%
          </span>
        </div>
      </div>

      {(isComplete || isError) && onDismiss && (
        <button
          onClick={() => onDismiss(downloadId)}
          className="flex-shrink-0 p-1 hover:bg-muted rounded"
          aria-label="Dismiss"
        >
          <X className="h-4 w-4 text-muted-foreground" />
        </button>
      )}
    </div>
  );
}

export function DownloadProgressIndicator({
  downloads,
  onDismiss,
}: DownloadProgressIndicatorProps) {
  const downloadEntries = Array.from(downloads.entries());

  if (downloadEntries.length === 0) {
    return null;
  }

  const activeCount = downloadEntries.filter(
    ([, d]) => d.phase !== 'complete' && d.phase !== 'error'
  ).length;

  return (
    <div className="fixed bottom-4 left-4 z-50 w-80 bg-card border rounded-lg shadow-lg overflow-hidden">
      {/* Header */}
      <div className="px-3 py-2 bg-muted/50 border-b">
        <div className="flex items-center gap-2">
          <Download className="h-4 w-4" />
          <span className="text-sm font-medium">
            {activeCount > 0
              ? `Downloading ${activeCount} file${activeCount > 1 ? 's' : ''}`
              : 'Downloads'}
          </span>
        </div>
      </div>

      {/* Download list */}
      <div className="max-h-60 overflow-y-auto">
        {downloadEntries.map(([downloadId, download]) => (
          <DownloadItem
            key={downloadId}
            downloadId={downloadId}
            download={download}
            onDismiss={onDismiss}
          />
        ))}
      </div>
    </div>
  );
}
