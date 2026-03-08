import { useEffect, useState, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Upload,
  FolderPlus,
  Grid,
  List,
  ChevronRight,
  ChevronUp,
  ChevronDown,
  Folder,
  File,
  MoreVertical,
  Download,
  Share2,
  Trash2,
  Edit,
  Loader2,
  AlertCircle,
  Check,
  Star,
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
import { CreateFolderDialog } from '@/components/files/CreateFolderDialog';
import { RenameDialog } from '@/components/files/RenameDialog';
import { FilePreviewDialog } from '@/components/files/FilePreviewDialog';
import { UploadProgressIndicator } from '@/components/files/UploadProgressIndicator';
import { DownloadProgressIndicator } from '@/components/files/DownloadProgressIndicator';
import { DropZoneOverlay } from '@/components/files/DropZoneOverlay';
import { FileFilters } from '@/components/files/FileFilters';
import { FileContextMenu } from '@/components/files/FileContextMenu';
import { FileGridView } from '@/components/files/FileGridView';
import { FileListSkeleton, FileGridSkeleton } from '@/components/files/FileListSkeleton';
import { ShareDialog } from '@/components/sharing/ShareDialog';
import { useToast } from '@/hooks/useToast';
import { useDropZone } from '@/hooks/useDropZone';
import { useKeyboardShortcuts, SHORTCUT_KEYS } from '@/hooks/useKeyboardShortcuts';
import { useTrayQuickUpload } from '@/hooks/useTray';
import { formatBytes, formatDate } from '@/lib/utils';
import { open, save } from '@tauri-apps/plugin-dialog';

// Local type that matches fileStore
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

export function FilesPage() {
  const { folderId } = useParams();
  const navigate = useNavigate();
  const {
    currentFolder,
    breadcrumbs,
    isLoading,
    error,
    previewFile,
    isLoadingPreview,
    previewError,
    uploadProgress,
    downloadProgress,
    searchQuery,
    filters,
    sortBy,
    sortOrder,
    loadFiles,
    uploadFile,
    downloadFile,
    createFolder,
    renameItem,
    deleteItem,
    clearError,
    loadPreview,
    clearPreview,
    dismissUpload,
    dismissDownload,
    setFilter,
    clearFilters,
    setSorting,
    getFilteredItems,
    selectedItems,
    toggleSelection,
    selectAll,
    clearSelection,
    viewMode,
    setViewMode,
  } = useFileStore();

  // Get filtered items
  const items = getFilteredItems();
  const hasActiveFilters = searchQuery !== '' || filters.type !== 'all' || filters.sharedStatus !== 'all';

  const { success, error: showError } = useToast();
  const { isFavorite, toggleFavorite } = useFavoritesStore();

  // Dialog states
  const [createFolderOpen, setCreateFolderOpen] = useState(false);
  const [renameDialogOpen, setRenameDialogOpen] = useState(false);
  const [shareDialogOpen, setShareDialogOpen] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [selectedItem, setSelectedItem] = useState<FileItem | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  useEffect(() => {
    loadFiles(folderId || null);
  }, [folderId, loadFiles]);

  // Handle dropped files - opens file dialog since we need system paths
  const handleDroppedFiles = async (files: File[]) => {
    if (files.length === 0) return;

    // For Tauri, we need system file paths which HTML5 drop doesn't provide
    // So we open the file dialog pre-filled with a hint
    success({
      title: 'Files detected',
      description: `${files.length} file(s) dropped. Opening file picker to select from your system.`,
    });

    // Open file dialog to let user select the files
    try {
      const selected = await open({
        multiple: true,
        directory: false,
      });

      if (selected) {
        const paths = Array.isArray(selected) ? selected : [selected];
        for (const path of paths) {
          await uploadFile(path, folderId || null);
        }
        success({ title: 'Upload complete', description: `${paths.length} file(s) uploaded` });
      }
    } catch (err) {
      showError({ title: 'Upload failed', description: String(err) });
    }
  };

  const { isDragOver, dropZoneProps } = useDropZone({
    onDrop: handleDroppedFiles,
    disabled: isLoading,
  });

  // Trigger upload from tray menu
  const triggerUpload = useCallback(async () => {
    try {
      const selected = await open({
        multiple: true,
        directory: false,
      });

      if (selected) {
        const paths = Array.isArray(selected) ? selected : [selected];
        for (const path of paths) {
          await uploadFile(path, folderId || null);
        }
        success({ title: 'Upload complete', description: `${paths.length} file(s) uploaded` });
      }
    } catch (err) {
      showError({ title: 'Upload failed', description: String(err) });
    }
  }, [folderId, uploadFile, success, showError]);

  // Listen for tray quick upload event
  useTrayQuickUpload(triggerUpload);

  const handleUpload = useCallback(async () => {
    try {
      const selected = await open({
        multiple: true,
        directory: false,
      });

      if (selected) {
        const paths = Array.isArray(selected) ? selected : [selected];
        for (const path of paths) {
          await uploadFile(path, folderId || null);
        }
        success({ title: 'Upload complete', description: `${paths.length} file(s) uploaded` });
      }
    } catch (err) {
      showError({ title: 'Upload failed', description: String(err) });
    }
  }, [folderId, uploadFile, success, showError]);

  const handleCreateFolder = async (name: string) => {
    await createFolder(name, folderId || null);
    success({ title: 'Folder created', description: `"${name}" has been created` });
  };

  const handleRename = async (itemId: string, newName: string) => {
    await renameItem(itemId, newName);
    success({ title: 'Renamed', description: `Item renamed to "${newName}"` });
  };

  const handleDownload = useCallback(async (item: FileItem) => {
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
  }, [downloadFile, success, showError]);

  const handleDelete = async () => {
    if (!selectedItem) return;

    setIsDeleting(true);
    try {
      await deleteItem(selectedItem.id);
      success({ title: 'Deleted', description: `"${selectedItem.name}" has been deleted` });
      setDeleteDialogOpen(false);
      setSelectedItem(null);
    } catch (err) {
      showError({ title: 'Delete failed', description: String(err) });
    } finally {
      setIsDeleting(false);
    }
  };

  const handleItemClick = useCallback((item: FileItem) => {
    if (item.item_type === 'folder') {
      navigate(`/files/${item.id}`);
    } else {
      loadPreview(item.id);
    }
  }, [navigate, loadPreview]);

  const openShareDialog = (item: FileItem) => {
    setSelectedItem(item);
    setShareDialogOpen(true);
  };

  const openRenameDialog = (item: FileItem) => {
    setSelectedItem(item);
    setRenameDialogOpen(true);
  };

  const openDeleteDialog = (item: FileItem) => {
    setSelectedItem(item);
    setDeleteDialogOpen(true);
  };

  // Handle keyboard shortcuts
  const handleDeleteShortcut = useCallback(() => {
    if (selectedItems.size === 0) return;
    // If only one item selected, use normal delete dialog
    if (selectedItems.size === 1) {
      const itemId = Array.from(selectedItems)[0];
      const item = items.find((i) => i.id === itemId);
      if (item) {
        openDeleteDialog(item);
      }
    } else {
      // Multiple items selected - show toast for now
      showError({
        title: 'Multiple selection',
        description: 'Please delete items one at a time',
      });
    }
  }, [selectedItems, items, showError]);

  const handleRenameShortcut = useCallback(() => {
    if (selectedItems.size !== 1) return;
    const itemId = Array.from(selectedItems)[0];
    const item = items.find((i) => i.id === itemId);
    if (item) {
      openRenameDialog(item);
    }
  }, [selectedItems, items]);

  const handleDownloadShortcut = useCallback(async () => {
    if (selectedItems.size !== 1) return;
    const itemId = Array.from(selectedItems)[0];
    const item = items.find((i) => i.id === itemId);
    if (item && item.item_type === 'file') {
      await handleDownload(item);
    }
  }, [selectedItems, items, handleDownload]);

  // Handle share shortcut
  const handleShareShortcut = useCallback(() => {
    if (selectedItems.size !== 1) return;
    const itemId = Array.from(selectedItems)[0];
    const item = items.find((i) => i.id === itemId);
    if (item) {
      openShareDialog(item);
    }
  }, [selectedItems, items]);

  // Handle open/enter shortcut
  const handleOpenShortcut = useCallback(() => {
    if (selectedItems.size !== 1) return;
    const itemId = Array.from(selectedItems)[0];
    const item = items.find((i) => i.id === itemId);
    if (item) {
      handleItemClick(item);
    }
  }, [selectedItems, items, handleItemClick]);

  // Handle new folder shortcut
  const handleNewFolderShortcut = useCallback(() => {
    setCreateFolderOpen(true);
  }, []);

  // Handle upload shortcut
  const handleUploadShortcut = useCallback(() => {
    handleUpload();
  }, [handleUpload]);

  // Setup keyboard shortcuts
  useKeyboardShortcuts([
    // Delete
    {
      key: SHORTCUT_KEYS.DELETE,
      action: handleDeleteShortcut,
    },
    {
      key: SHORTCUT_KEYS.BACKSPACE,
      action: handleDeleteShortcut,
    },
    // Selection
    {
      key: SHORTCUT_KEYS.A,
      ctrl: true,
      action: selectAll,
    },
    {
      key: SHORTCUT_KEYS.ESCAPE,
      action: clearSelection,
    },
    // Rename
    {
      key: SHORTCUT_KEYS.F2,
      action: handleRenameShortcut,
    },
    // Download
    {
      key: SHORTCUT_KEYS.D,
      ctrl: true,
      action: handleDownloadShortcut,
    },
    // Share
    {
      key: SHORTCUT_KEYS.S,
      ctrl: true,
      shift: true,
      action: handleShareShortcut,
    },
    // Open/Enter
    {
      key: SHORTCUT_KEYS.ENTER,
      action: handleOpenShortcut,
    },
    {
      key: SHORTCUT_KEYS.O,
      ctrl: true,
      action: handleOpenShortcut,
    },
    // New folder
    {
      key: SHORTCUT_KEYS.N,
      ctrl: true,
      shift: true,
      action: handleNewFolderShortcut,
    },
    // Upload
    {
      key: SHORTCUT_KEYS.U,
      ctrl: true,
      action: handleUploadShortcut,
    },
    // Toggle view
    {
      key: SHORTCUT_KEYS.G,
      ctrl: true,
      action: () => setViewMode('grid'),
    },
    {
      key: SHORTCUT_KEYS.L,
      ctrl: true,
      action: () => setViewMode('list'),
    },
  ]);

  // Convert fileStore item to ShareDialog compatible type
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

  // Convert for RenameDialog
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

  return (
    <div className="space-y-6" {...dropZoneProps}>
      {/* Drop Zone Overlay */}
      <DropZoneOverlay isVisible={isDragOver} />

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">
            {currentFolder?.name || 'My Files'}
          </h1>
          {/* Breadcrumbs */}
          <div className="flex items-center text-sm text-muted-foreground mt-1">
            <button
              onClick={() => navigate('/files')}
              className="hover:text-foreground"
            >
              My Files
            </button>
            {breadcrumbs.map((crumb) => (
              <span key={crumb.id} className="flex items-center">
                <ChevronRight className="h-4 w-4 mx-1" />
                <button
                  onClick={() => navigate(`/files/${crumb.id}`)}
                  className="hover:text-foreground"
                >
                  {crumb.name}
                </button>
              </span>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Button
            variant={viewMode === 'grid' ? 'default' : 'outline'}
            size="icon"
            onClick={() => setViewMode('grid')}
            aria-label="Grid view"
          >
            <Grid className="h-4 w-4" />
          </Button>
          <Button
            variant={viewMode === 'list' ? 'default' : 'outline'}
            size="icon"
            onClick={() => setViewMode('list')}
            aria-label="List view"
          >
            <List className="h-4 w-4" />
          </Button>
          <Button variant="outline" onClick={() => setCreateFolderOpen(true)}>
            <FolderPlus className="h-4 w-4 mr-2" />
            New Folder
          </Button>
          <Button onClick={handleUpload}>
            <Upload className="h-4 w-4 mr-2" />
            Upload
          </Button>
        </div>
      </div>

      {/* Filters */}
      <FileFilters
        typeFilter={filters.type}
        sharedStatusFilter={filters.sharedStatus}
        onTypeFilterChange={(value) => setFilter('type', value)}
        onSharedStatusFilterChange={(value) => setFilter('sharedStatus', value)}
        onClearFilters={clearFilters}
        hasActiveFilters={hasActiveFilters}
      />

      {/* Error Banner */}
      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-red-800 dark:border-red-900 dark:bg-red-900/20 dark:text-red-400">
          <AlertCircle className="h-5 w-5" />
          <span>{error}</span>
          <Button size="sm" variant="ghost" onClick={clearError}>
            Dismiss
          </Button>
        </div>
      )}

      {/* File list */}
      {isLoading ? (
        viewMode === 'grid' ? <FileGridSkeleton /> : <FileListSkeleton />
      ) : items.length === 0 ? (
        <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
          <Folder className="h-16 w-16 mb-4 opacity-50" />
          <p className="text-lg">No files yet</p>
          <p className="text-sm">Upload files or create a folder to get started</p>
        </div>
      ) : viewMode === 'grid' ? (
        <FileGridView
          items={items}
          selectedItems={selectedItems}
          onItemClick={handleItemClick}
          onToggleSelection={toggleSelection}
          onDownload={handleDownload}
          onShare={openShareDialog}
          onRename={openRenameDialog}
          onDelete={openDeleteDialog}
        />
      ) : (
        <div className="border rounded-lg overflow-hidden">
          <table className="w-full">
            <thead className="bg-muted/50">
              <tr className="text-left text-sm">
                <th className="px-4 py-3 w-10">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      if (selectedItems.size === items.length) {
                        clearSelection();
                      } else {
                        selectAll();
                      }
                    }}
                    className={`w-5 h-5 rounded border flex items-center justify-center transition-colors ${
                      selectedItems.size === items.length && items.length > 0
                        ? 'bg-primary border-primary text-primary-foreground'
                        : 'border-input hover:border-primary'
                    }`}
                    aria-label={selectedItems.size === items.length ? 'Deselect all' : 'Select all'}
                  >
                    {selectedItems.size === items.length && items.length > 0 && (
                      <Check className="h-3 w-3" />
                    )}
                  </button>
                </th>
                <th
                  className="px-4 py-3 font-medium cursor-pointer hover:bg-muted/80 select-none"
                  onClick={() => setSorting('name')}
                >
                  <div className="flex items-center gap-1">
                    Name
                    {sortBy === 'name' && (
                      sortOrder === 'asc' ? (
                        <ChevronUp className="h-4 w-4" />
                      ) : (
                        <ChevronDown className="h-4 w-4" />
                      )
                    )}
                  </div>
                </th>
                <th
                  className="px-4 py-3 font-medium cursor-pointer hover:bg-muted/80 select-none"
                  onClick={() => setSorting('size')}
                >
                  <div className="flex items-center gap-1">
                    Size
                    {sortBy === 'size' && (
                      sortOrder === 'asc' ? (
                        <ChevronUp className="h-4 w-4" />
                      ) : (
                        <ChevronDown className="h-4 w-4" />
                      )
                    )}
                  </div>
                </th>
                <th
                  className="px-4 py-3 font-medium cursor-pointer hover:bg-muted/80 select-none"
                  onClick={() => setSorting('updated_at')}
                >
                  <div className="flex items-center gap-1">
                    Modified
                    {sortBy === 'updated_at' && (
                      sortOrder === 'asc' ? (
                        <ChevronUp className="h-4 w-4" />
                      ) : (
                        <ChevronDown className="h-4 w-4" />
                      )
                    )}
                  </div>
                </th>
                <th className="px-4 py-3 font-medium w-12"></th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {items.map((item) => (
                <FileContextMenu
                  key={item.id}
                  item={item}
                  onDownload={() => handleDownload(item)}
                  onShare={() => openShareDialog(item)}
                  onRename={() => openRenameDialog(item)}
                  onDelete={() => openDeleteDialog(item)}
                >
                  <tr
                    className={`hover:bg-muted/50 cursor-pointer ${
                      selectedItems.has(item.id) ? 'bg-primary/10' : ''
                    }`}
                    onClick={(e) => {
                      if (e.ctrlKey || e.metaKey) {
                        toggleSelection(item.id);
                      } else {
                        handleItemClick(item);
                      }
                    }}
                  >
                    <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                      <button
                        onClick={() => toggleSelection(item.id)}
                        className={`w-5 h-5 rounded border flex items-center justify-center transition-colors ${
                          selectedItems.has(item.id)
                            ? 'bg-primary border-primary text-primary-foreground'
                            : 'border-input hover:border-primary'
                        }`}
                        aria-label={selectedItems.has(item.id) ? 'Deselect' : 'Select'}
                      >
                        {selectedItems.has(item.id) && <Check className="h-3 w-3" />}
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        {item.item_type === 'folder' ? (
                          <Folder className="h-5 w-5 text-primary" />
                        ) : (
                          <File className="h-5 w-5 text-muted-foreground" />
                        )}
                        <span className="font-medium">{item.name}</span>
                        {isFavorite(item.id) && (
                          <Star className="h-4 w-4 text-yellow-500 fill-yellow-500" />
                        )}
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
                            openShareDialog(item);
                          }}
                        >
                          <Share2 className="mr-2 h-4 w-4" />
                          Share
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          onClick={(e) => {
                            e.stopPropagation();
                            openRenameDialog(item);
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
                            openDeleteDialog(item);
                          }}
                        >
                          <Trash2 className="mr-2 h-4 w-4" />
                          Delete
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  </td>
                  </tr>
                </FileContextMenu>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Dialogs */}
      <CreateFolderDialog
        open={createFolderOpen}
        onOpenChange={setCreateFolderOpen}
        onCreateFolder={handleCreateFolder}
      />

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

      {/* Upload Progress Indicator */}
      <UploadProgressIndicator
        uploads={uploadProgress}
        onDismiss={dismissUpload}
      />

      {/* Download Progress Indicator */}
      <DownloadProgressIndicator
        downloads={downloadProgress}
        onDismiss={dismissDownload}
      />
    </div>
  );
}
