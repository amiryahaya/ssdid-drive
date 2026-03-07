import { Loader2, Eye, FileWarning } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog';

interface FilePreview {
  file_id: string;
  file_name: string;
  mime_type: string;
  preview_data: string | null;
  can_preview: boolean;
}

interface FilePreviewDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  preview: FilePreview | null;
  isLoading: boolean;
  error?: string | null;
}

function isTextMimeType(mimeType: string): boolean {
  return (
    mimeType.startsWith('text/') ||
    mimeType === 'application/json' ||
    mimeType === 'application/xml' ||
    mimeType === 'application/javascript' ||
    mimeType === 'application/typescript'
  );
}

function PreviewContent({ preview }: { preview: FilePreview }) {
  if (!preview.can_preview || !preview.preview_data) {
    return (
      <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
        <FileWarning className="h-16 w-16 mb-4 opacity-50" />
        <p className="text-lg font-medium">Preview not available</p>
        <p className="text-sm">This file type cannot be previewed</p>
      </div>
    );
  }

  const dataUrl = `data:${preview.mime_type};base64,${preview.preview_data}`;

  // Image preview
  if (preview.mime_type.startsWith('image/')) {
    return (
      <div className="flex items-center justify-center max-h-[70vh] overflow-auto">
        <img
          src={dataUrl}
          alt={preview.file_name}
          className="max-w-full h-auto object-contain"
        />
      </div>
    );
  }

  // PDF preview
  if (preview.mime_type === 'application/pdf') {
    return (
      <div className="w-full h-[70vh]">
        <embed
          src={dataUrl}
          type="application/pdf"
          className="w-full h-full"
        />
      </div>
    );
  }

  // Text/Code preview
  if (isTextMimeType(preview.mime_type)) {
    try {
      const textContent = atob(preview.preview_data);
      return (
        <div className="max-h-[70vh] overflow-auto">
          <pre className="p-4 bg-muted rounded-md text-sm whitespace-pre-wrap break-words font-mono">
            {textContent}
          </pre>
        </div>
      );
    } catch {
      return (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <FileWarning className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg font-medium">Failed to decode content</p>
        </div>
      );
    }
  }

  // Unsupported type
  return (
    <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
      <FileWarning className="h-16 w-16 mb-4 opacity-50" />
      <p className="text-lg font-medium">Preview not available</p>
      <p className="text-sm">This file type ({preview.mime_type}) cannot be previewed</p>
    </div>
  );
}

export function FilePreviewDialog({
  open,
  onOpenChange,
  preview,
  isLoading,
  error,
}: FilePreviewDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[800px] max-h-[90vh]">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 pr-8">
            <Eye className="h-5 w-5" />
            <span className="truncate">
              {isLoading ? 'Loading preview...' : preview?.file_name || 'File Preview'}
            </span>
          </DialogTitle>
        </DialogHeader>

        <div className="mt-4">
          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center h-64 text-destructive">
              <FileWarning className="h-16 w-16 mb-4 opacity-50" />
              <p className="text-lg font-medium">Failed to load preview</p>
              <p className="text-sm">{error}</p>
            </div>
          ) : preview ? (
            <PreviewContent preview={preview} />
          ) : null}
        </div>
      </DialogContent>
    </Dialog>
  );
}
