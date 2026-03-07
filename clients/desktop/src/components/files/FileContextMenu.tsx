import { ReactNode } from 'react';
import { Download, Share2, Edit, Trash2, Star, StarOff } from 'lucide-react';
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from '@/components/ui/ContextMenu';
import { useFavoritesStore } from '@/stores/favoritesStore';

interface FileItem {
  id: string;
  name: string;
  item_type: 'file' | 'folder';
}

interface FileContextMenuProps {
  item: FileItem;
  onDownload: () => void;
  onShare: () => void;
  onRename: () => void;
  onDelete: () => void;
  children: ReactNode;
}

export function FileContextMenu({
  item,
  onDownload,
  onShare,
  onRename,
  onDelete,
  children,
}: FileContextMenuProps) {
  const { isFavorite, toggleFavorite } = useFavoritesStore();
  const isItemFavorite = isFavorite(item.id);

  return (
    <ContextMenu>
      <ContextMenuTrigger asChild>{children}</ContextMenuTrigger>
      <ContextMenuContent className="w-48">
        <ContextMenuItem onClick={() => toggleFavorite(item.id)}>
          {isItemFavorite ? (
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
        </ContextMenuItem>
        <ContextMenuSeparator />
        {item.item_type === 'file' && (
          <ContextMenuItem onClick={onDownload}>
            <Download className="mr-2 h-4 w-4" />
            Download
          </ContextMenuItem>
        )}
        <ContextMenuItem onClick={onShare}>
          <Share2 className="mr-2 h-4 w-4" />
          Share
        </ContextMenuItem>
        <ContextMenuItem onClick={onRename}>
          <Edit className="mr-2 h-4 w-4" />
          Rename
        </ContextMenuItem>
        <ContextMenuSeparator />
        <ContextMenuItem onClick={onDelete} className="text-destructive">
          <Trash2 className="mr-2 h-4 w-4" />
          Delete
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>
  );
}
