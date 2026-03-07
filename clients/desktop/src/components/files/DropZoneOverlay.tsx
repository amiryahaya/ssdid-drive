import { Upload } from 'lucide-react';

interface DropZoneOverlayProps {
  isVisible: boolean;
}

export function DropZoneOverlay({ isVisible }: DropZoneOverlayProps) {
  if (!isVisible) return null;

  return (
    <div className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm flex items-center justify-center animate-in fade-in duration-200">
      <div className="flex flex-col items-center justify-center p-12 border-4 border-dashed border-primary rounded-2xl bg-card">
        <Upload className="h-16 w-16 text-primary mb-4 animate-bounce" />
        <h2 className="text-2xl font-bold text-foreground mb-2">Drop files to upload</h2>
        <p className="text-muted-foreground">Release to start uploading your files</p>
      </div>
    </div>
  );
}
