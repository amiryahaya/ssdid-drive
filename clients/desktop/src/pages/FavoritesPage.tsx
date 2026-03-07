import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Star,
  Folder,
  File,
  Download,
  Share2,
  Trash2,
  Edit,
  MoreVertical,
  Loader2,
  StarOff,
} from 'lucide-react';
import { useFileStore } from '@/stores/fileStore';
import { useFavoritesStore } from '@/stores/favoritesStore';
import { Button } from '@/components/ui/Button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/DropdownMenu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { RenameDialog } from '@/components/files/RenameDialog';
import { FilePreviewDialog } from '@/components/files/FilePreviewDialog';
import { ShareDialog } from '@/components/sharing/ShareDialog';
import { useToast } from '@/hooks/useToast';
import { formatBytes, formatDate } from '@/lib/utils';
import { invoke } from '@tauri-apps/api/core';
import { save } from '@tauri-apps/plugin-dialog';

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

export function FavoritesPage() {
  const navigate = useNavigate();
  const { success, error: showError } = useToast();
  const { favorites, removeFavorite } = useFavoritesStore();
  const {
    previewFile,
    isLoadingPreview,
    previewError,
    loadPreview,
    clearPreview,
    downloadFile,
    renameItem,
    deleteItem,
  } = useFileStore();

  const [favoriteItems, setFavoriteItems] = useState<FileItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedItem, setSelectedItem] = useState<FileItem | null>(null);
  const [renameDialogOpen, setRenameDialogOpen] = useState(false);
  const [shareDialogOpen, setShareDialogOpen] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);

  // Load favorite items
  useEffect(() => {
    const loadFavorites = async () => {
      setIsLoading(true);
      const favoriteIds = Array.from(favorites);

      if (favoriteIds.length === 0) {
        setFavoriteItems([]);
        setIsLoading(false);
        return;
      }

      try {
        // Load all files and filter by favorites
        const response = await invoke<{ items: FileItem[] }>('list_files', {
          folderId: null,
        });

        // We need to search recursively or just show root-level favorites
        // For now, filter items that are in favorites
        const favItems = response.items.filter((item) => favorites.has(item.id));
        setFavoriteItems(favItems);
      } catch (err) {
        console.error('Failed to load favorites:', err);
      } finally {
        setIsLoading(false);
      }
    };

    loadFavorites();
  }, [favorites]);

  const handleItemClick = (item: FileItem) => {
    if (item.item_type === 'folder') {
      navigate(`/files/${item.id}`);
    } else {
      loadPreview(item.id);
    }
  };

  const handleDownload = async (item: FileItem) => {
    try {
      const destination = await save({
        defaultPath: item.name,
      });

      if (destination) {
        await downloadFile(item.id, destination, item.name);
        success({ title: 'Download complete', description: `"${item.name}" saved successfully` });
      }
    } catch (err) {
      showError({ title: 'Download failed', description: String(err) });
    }
  };

  const handleRename = async (itemId: string, newName: string) => {
    await renameItem(itemId, newName);
    // Update local state
    setFavoriteItems((items) =>
      items.map((item) => (item.id === itemId ? { ...item, name: newName } : item))
    );
    success({ title: 'Renamed', description: `Item renamed to "${newName}"` });
  };

  const handleDelete = async () => {
    if (!selectedItem) return;

    setIsDeleting(true);
    try {
      await deleteItem(selectedItem.id);
      removeFavorite(selectedItem.id);
      setFavoriteItems((items) => items.filter((item) => item.id !== selectedItem.id));
      success({ title: 'Deleted', description: `"${selectedItem.name}" has been deleted` });
      setDeleteDialogOpen(false);
      setSelectedItem(null);
    } catch (err) {
      showError({ title: 'Delete failed', description: String(err) });
    } finally {
      setIsDeleting(false);
    }
  };

  const handleRemoveFromFavorites = (item: FileItem) => {
    removeFavorite(item.id);
    setFavoriteItems((items) => items.filter((i) => i.id !== item.id));
    success({ title: 'Removed from favorites', description: `"${item.name}" removed from favorites` });
  };

  const renameDialogItem = selectedItem
    ? {
        id: selectedItem.id,
        name: selectedItem.name,
        type: selectedItem.item_type as 'file' | 'folder',
        size: selectedItem.size,
        mime_type: selectedItem.mime_type,
        folder_id: selectedItem.folder_id,
        is_shared: selectedItem.is_shared,
        created_at: selectedItem.created_at,
        updated_at: selectedItem.updated_at,
      }
    : null;

  const shareDialogItem = selectedItem
    ? {
        id: selectedItem.id,
        name: selectedItem.name,
        type: selectedItem.item_type as 'file' | 'folder',
        size: selectedItem.size,
        mime_type: selectedItem.mime_type,
        folder_id: selectedItem.folder_id,
        is_shared: selectedItem.is_shared,
        created_at: selectedItem.created_at,
        updated_at: selectedItem.updated_at,
      }
    : null;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Star className="h-6 w-6 text-yellow-500 fill-yellow-500" />
          Favorites
        </h1>
        <p className="text-muted-foreground mt-1">
          Quick access to your starred files and folders
        </p>
      </div>

      {/* Content */}
      {isLoading ? (
        <div className="flex items-center justify-center h-64">
          <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
        </div>
      ) : favoriteItems.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <Star className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg">No favorites yet</p>
          <p className="text-sm">Star files and folders for quick access</p>
        </div>
      ) : (
        <div className="border rounded-lg overflow-hidden">
          <table className="w-full">
            <thead className="bg-muted/50">
              <tr className="text-left text-sm">
                <th className="px-4 py-3 font-medium">Name</th>
                <th className="px-4 py-3 font-medium">Size</th>
                <th className="px-4 py-3 font-medium">Modified</th>
                <th className="px-4 py-3 font-medium w-12"></th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {favoriteItems.map((item) => (
                <tr
                  key={item.id}
                  className="hover:bg-muted/50 cursor-pointer"
                  onClick={() => handleItemClick(item)}
                >
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-3">
                      {item.item_type === 'folder' ? (
                        <Folder className="h-5 w-5 text-primary" />
                      ) : (
                        <File className="h-5 w-5 text-muted-foreground" />
                      )}
                      <span className="font-medium">{item.name}</span>
                      <Star className="h-4 w-4 text-yellow-500 fill-yellow-500" />
                      {item.is_shared && (
                        <Share2 className="h-4 w-4 text-muted-foreground" />
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-sm text-muted-foreground">
                    {item.item_type === 'folder' ? '-' : formatBytes(item.size)}
                  </td>
                  <td className="px-4 py-3 text-sm text-muted-foreground">
                    {formatDate(item.updated_at)}
                  </td>
                  <td className="px-4 py-3">
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={(e) => e.stopPropagation()}
                        >
                          <MoreVertical className="h-4 w-4" />
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem
                          onClick={(e) => {
                            e.stopPropagation();
                            handleRemoveFromFavorites(item);
                          }}
                        >
                          <StarOff className="mr-2 h-4 w-4" />
                          Remove from Favorites
                        </DropdownMenuItem>
                        {item.item_type === 'file' && (
                          <DropdownMenuItem
                            onClick={(e) => {
                              e.stopPropagation();
                              handleDownload(item);
                            }}
                          >
                            <Download className="mr-2 h-4 w-4" />
                            Download
                          </DropdownMenuItem>
                        )}
                        <DropdownMenuItem
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedItem(item);
                            setShareDialogOpen(true);
                          }}
                        >
                          <Share2 className="mr-2 h-4 w-4" />
                          Share
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          onClick={(e) => {
                            e.stopPropagation();
                            setSelectedItem(item);
                            setRenameDialogOpen(true);
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
                            setSelectedItem(item);
                            setDeleteDialogOpen(true);
                          }}
                        >
                          <Trash2 className="mr-2 h-4 w-4" />
                          Delete
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Dialogs */}
      <RenameDialog
        open={renameDialogOpen}
        onOpenChange={setRenameDialogOpen}
        item={renameDialogItem}
        onRename={handleRename}
      />

      <ShareDialog
        open={shareDialogOpen}
        onOpenChange={setShareDialogOpen}
        item={shareDialogItem}
      />

      <FilePreviewDialog
        open={previewFile !== null || isLoadingPreview}
        onOpenChange={(open) => {
          if (!open) clearPreview();
        }}
        preview={previewFile}
        isLoading={isLoadingPreview}
        error={previewError}
      />

      {/* Delete Confirmation Dialog */}
      <Dialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete {selectedItem?.item_type === 'folder' ? 'Folder' : 'File'}</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete "{selectedItem?.name}"?
              {selectedItem?.item_type === 'folder' && ' This will also delete all contents.'}
              {' '}This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteDialogOpen(false)}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={handleDelete} disabled={isDeleting}>
              {isDeleting && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
