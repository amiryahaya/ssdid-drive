import {
  Folder,
  File,
  MoreVertical,
  Download,
  Share2,
  Trash2,
  Edit,
  Check,
  Star,
  StarOff,
} from 'lucide-react';
import { Button } from '@/components/ui/Button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu';
import { FileContextMenu } from './FileContextMenu';
import { useFavoritesStore } from '@/stores/favoritesStore';
import { formatBytes } from '@/lib/utils';

interface FileItem {
  id: string;
  name: string;
  item_type: 'file' | 'folder';
  size: number;
  mime_type: string | null;
  folder_id: string | null;
  owner_id: string;
  created_at: string;
  updated_at: string;
  is_shared: boolean;
  is_received_share: boolean;
}

interface FileGridViewProps {
  items: FileItem[];
  selectedItems: Set<string>;
  onItemClick: (item: FileItem) => void;
  onToggleSelection: (id: string) => void;
  onDownload: (item: FileItem) => void;
  onShare: (item: FileItem) => void;
  onRename: (item: FileItem) => void;
  onDelete: (item: FileItem) => void;
}

export function FileGridView({
  items,
  selectedItems,
  onItemClick,
  onToggleSelection,
  onDownload,
  onShare,
  onRename,
  onDelete,
}: FileGridViewProps) {
  const { isFavorite, toggleFavorite } = useFavoritesStore();

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
      {items.map((item) => (
        <FileContextMenu
          key={item.id}
          item={item}
          onDownload={() => onDownload(item)}
          onShare={() => onShare(item)}
          onRename={() => onRename(item)}
          onDelete={() => onDelete(item)}
        >
          <div
            className={`group relative p-4 rounded-lg border cursor-pointer transition-colors hover:bg-muted/50 ${
              selectedItems.has(item.id) ? 'bg-primary/10 border-primary' : 'border-border'
            }`}
            onClick={(e) => {
              if (e.ctrlKey || e.metaKey) {
                onToggleSelection(item.id);
              } else {
                onItemClick(item);
              }
            }}
          >
            {/* Selection checkbox */}
            <button
              onClick={(e) => {
                e.stopPropagation();
                onToggleSelection(item.id);
              }}
              className={`absolute top-2 left-2 w-5 h-5 rounded border flex items-center justify-center transition-colors opacity-0 group-hover:opacity-100 ${
                selectedItems.has(item.id)
                  ? 'bg-primary border-primary text-primary-foreground opacity-100'
                  : 'border-input hover:border-primary bg-background'
              }`}
              aria-label={selectedItems.has(item.id) ? 'Deselect' : 'Select'}
            >
              {selectedItems.has(item.id) && <Check className="h-3 w-3" />}
            </button>

            {/* Actions menu */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="absolute top-2 right-2 h-7 w-7 opacity-0 group-hover:opacity-100"
                  onClick={(e) => e.stopPropagation()}
                >
                  <MoreVertical className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem
                  onClick={(e) => {
                    e.stopPropagation();
                    toggleFavorite(item.id);
                  }}
                >
                  {isFavorite(item.id) ? (
                    <>
                      <StarOff className="mr-2 h-4 w-4" />
                      Remove from Favorites
                    </>
                  ) : (
                    <>
                      <Star className="mr-2 h-4 w-4" />
                      Add to Favorites
                    </>
                  )}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                {item.item_type === 'file' && (
                  <DropdownMenuItem
                    onClick={(e) => {
                      e.stopPropagation();
                      onDownload(item);
                    }}
                  >
                    <Download className="mr-2 h-4 w-4" />
                    Download
                  </DropdownMenuItem>
                )}
                <DropdownMenuItem
                  onClick={(e) => {
                    e.stopPropagation();
                    onShare(item);
                  }}
                >
                  <Share2 className="mr-2 h-4 w-4" />
                  Share
                </DropdownMenuItem>
                <DropdownMenuItem
                  onClick={(e) => {
                    e.stopPropagation();
                    onRename(item);
                  }}
                >
                  <Edit className="mr-2 h-4 w-4" />
                  Rename
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  className="text-destructive"
                  onClick={(e) => {
                    e.stopPropagation();
                    onDelete(item);
                  }}
                >
                  <Trash2 className="mr-2 h-4 w-4" />
                  Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>

            {/* Icon */}
            <div className="flex flex-col items-center pt-4">
              {item.item_type === 'folder' ? (
                <Folder className="h-12 w-12 text-primary mb-3" />
              ) : (
                <File className="h-12 w-12 text-muted-foreground mb-3" />
              )}

              {/* Name */}
              <div className="w-full text-center">
                <p className="text-sm font-medium truncate" title={item.name}>
                  {item.name}
                </p>
                <p className="text-xs text-muted-foreground mt-1">
                  {item.item_type === 'folder' ? 'Folder' : formatBytes(item.size)}
                </p>
              </div>

              {/* Status indicators */}
              <div className="absolute bottom-2 right-2 flex items-center gap-1">
                {isFavorite(item.id) && (
                  <Star className="h-4 w-4 text-yellow-500 fill-yellow-500" />
                )}
                {item.is_shared && (
                  <Share2 className="h-4 w-4 text-muted-foreground" />
                )}
              </div>
            </div>
          </div>
        </FileContextMenu>
      ))}
    </div>
  );
}
