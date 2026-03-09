import { create } from 'zustand';
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';
import tauriService from '../services/tauri';

interface FilePreview {
  file_id: string;
  file_name: string;
  mime_type: string;
  preview_data: string | null;
  can_preview: boolean;
}

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

interface FolderInfo {
  id: string;
  name: string;
  parent_id: string | null;
}

interface FileListResponse {
  items: FileItem[];
  current_folder: FolderInfo | null;
  breadcrumbs: FolderInfo[];
}

interface UploadProgress {
  file_id: string;
  file_name: string;
  phase: 'preparing' | 'encrypting' | 'uploading' | 'confirming' | 'complete' | 'error';
  bytes_uploaded: number;
  total_bytes: number;
  progress_percent: number;
}

interface DownloadProgress {
  file_id: string;
  file_name: string;
  phase: 'preparing' | 'downloading' | 'decrypting' | 'writing' | 'complete' | 'error';
  bytes_downloaded: number;
  total_bytes: number;
  progress_percent: number;
}

type FileTypeFilter = 'all' | 'file' | 'folder';
type SharedStatusFilter = 'all' | 'shared' | 'not_shared' | 'received';
type SortField = 'name' | 'size' | 'updated_at';
type SortOrder = 'asc' | 'desc';
type ViewMode = 'list' | 'grid';

interface FileFilters {
  type: FileTypeFilter;
  sharedStatus: SharedStatusFilter;
}

interface FileState {
  items: FileItem[];
  currentFolder: FolderInfo | null;
  breadcrumbs: FolderInfo[];
  isLoading: boolean;
  error: string | null;
  uploadProgress: Map<string, UploadProgress>;
  downloadProgress: Map<string, DownloadProgress>;

  // Search, filter, and sort state
  searchQuery: string;
  filters: FileFilters;
  sortBy: SortField;
  sortOrder: SortOrder;

  // View mode state
  viewMode: ViewMode;

  // Selection state
  selectedItems: Set<string>;
  selectItem: (id: string) => void;
  toggleSelection: (id: string) => void;
  selectAll: () => void;
  clearSelection: () => void;

  // Preview state
  previewFile: FilePreview | null;
  isLoadingPreview: boolean;
  previewError: string | null;

  // Actions
  loadFiles: (folderId?: string | null) => Promise<void>;
  uploadFile: (path: string, folderId?: string | null) => Promise<void>;
  downloadFile: (fileId: string, destination: string, fileName: string) => Promise<void>;
  createFolder: (name: string, parentId?: string | null) => Promise<void>;
  deleteItem: (itemId: string) => Promise<void>;
  renameItem: (itemId: string, newName: string) => Promise<void>;
  moveItem: (itemId: string, newFolderId: string | null) => Promise<void>;
  navigateToFolder: (folderId: string | null) => void;
  clearError: () => void;

  // Preview actions
  loadPreview: (fileId: string) => Promise<void>;
  clearPreview: () => void;

  // Progress actions
  dismissUpload: (uploadId: string) => void;
  dismissDownload: (downloadId: string) => void;

  // Search, filter, and sort actions
  setSearchQuery: (query: string) => void;
  setFilter: <K extends keyof FileFilters>(key: K, value: FileFilters[K]) => void;
  clearFilters: () => void;
  setSorting: (field: SortField) => void;
  setViewMode: (mode: ViewMode) => void;
  getFilteredItems: () => FileItem[];
}

export const useFileStore = create<FileState>((set, get) => ({
  items: [],
  currentFolder: null,
  breadcrumbs: [],
  isLoading: false,
  error: null,
  uploadProgress: new Map(),
  downloadProgress: new Map(),

  // Search, filter, and sort state
  searchQuery: '',
  filters: {
    type: 'all',
    sharedStatus: 'all',
  },
  sortBy: 'name',
  sortOrder: 'asc',

  // View mode
  viewMode: 'list',

  // Selection state
  selectedItems: new Set<string>(),

  // Preview state
  previewFile: null,
  isLoadingPreview: false,
  previewError: null,

  loadFiles: async (folderId) => {
    set({ isLoading: true, error: null });
    try {
      const response = await invoke<FileListResponse>('list_files', {
        folderId: folderId ?? null,
      });
      set({
        items: response.items,
        currentFolder: response.current_folder,
        breadcrumbs: response.breadcrumbs,
        isLoading: false,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message, isLoading: false });
    }
  },

  uploadFile: async (path, folderId) => {
    const uploadId = crypto.randomUUID();
    const fileId = crypto.randomUUID();

    // Listen for progress events
    let unlisten: UnlistenFn | null = null;
    try {
      unlisten = await listen<UploadProgress>('upload-progress', (event) => {
        set((state) => ({
          uploadProgress: new Map(state.uploadProgress).set(uploadId, event.payload),
        }));
      });

      // Encrypt the file before upload if we have a folder context
      let uploadPath = path;
      let encryptionMeta: { file_key: string; nonce: string; algorithm: string } | null = null;

      const targetFolderId = folderId ?? get().currentFolder?.id ?? null;
      if (targetFolderId) {
        try {
          // 1. Get folder encryption metadata (KEM ciphertext + wrapped folder key)
          const folderMeta = await tauriService.getFolderEncryptionMetadata(targetFolderId);

          // 2. Decapsulate the folder key using user's KEM secret keys
          const { folder_key: folderKey } = await tauriService.decapsulateFolderKey(
            folderMeta.kem_ciphertext,
            folderMeta.wrapped_folder_key,
            folderMeta.encrypted_ml_kem_sk,
            folderMeta.encrypted_kaz_kem_sk,
          );

          // 3. Encrypt the file: derives file key via HKDF(folder_key, file_id),
          //    then encrypts content with AES-256-GCM
          const encryptResult = await tauriService.encryptFile(path, folderKey, fileId);
          uploadPath = encryptResult.ciphertext_path;
          encryptionMeta = {
            file_key: encryptResult.file_key,
            nonce: encryptResult.nonce,
            algorithm: 'AES-256-GCM',
          };
        } catch (encryptError) {
          // Log but don't block upload — graceful fallback to unencrypted
          console.warn('File encryption failed, uploading without encryption:', encryptError);
        }
      }

      await invoke('upload_file', {
        filePath: uploadPath,
        folderId: targetFolderId,
        fileName: null,
        fileId,
        encryptedFileKey: encryptionMeta?.file_key ?? null,
        nonce: encryptionMeta?.nonce ?? null,
        algorithm: encryptionMeta?.algorithm ?? null,
      });

      // Refresh file list
      await get().loadFiles(get().currentFolder?.id ?? null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    } finally {
      if (unlisten) unlisten();
      set((state) => {
        const newProgress = new Map(state.uploadProgress);
        newProgress.delete(uploadId);
        return { uploadProgress: newProgress };
      });
    }
  },

  downloadFile: async (fileId, destination, fileName) => {
    const downloadId = crypto.randomUUID();

    // Initialize progress
    set((state) => ({
      downloadProgress: new Map(state.downloadProgress).set(downloadId, {
        file_id: fileId,
        file_name: fileName,
        phase: 'preparing',
        bytes_downloaded: 0,
        total_bytes: 0,
        progress_percent: 0,
      }),
    }));

    // Listen for progress events
    let unlisten: UnlistenFn | null = null;
    try {
      unlisten = await listen<DownloadProgress>('download-progress', (event) => {
        set((state) => ({
          downloadProgress: new Map(state.downloadProgress).set(downloadId, event.payload),
        }));
      });

      await invoke('download_file', { fileId, destination });

      // Mark as complete
      set((state) => {
        const progress = state.downloadProgress.get(downloadId);
        if (progress) {
          return {
            downloadProgress: new Map(state.downloadProgress).set(downloadId, {
              ...progress,
              phase: 'complete',
              progress_percent: 100,
            }),
          };
        }
        return state;
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      // Mark as error
      set((state) => {
        const progress = state.downloadProgress.get(downloadId);
        if (progress) {
          return {
            error: message,
            downloadProgress: new Map(state.downloadProgress).set(downloadId, {
              ...progress,
              phase: 'error',
            }),
          };
        }
        return { error: message };
      });
      throw error;
    } finally {
      if (unlisten) unlisten();
    }
  },

  createFolder: async (name, parentId) => {
    try {
      // Fetch user's KEM public keys for folder key encapsulation
      const keys = await invoke<{ ml_kem_pk: string; kaz_kem_pk: string }>('get_user_kem_public_keys');

      await invoke('create_folder', {
        name,
        parentId: parentId ?? null,
        mlKemPk: keys.ml_kem_pk,
        kazKemPk: keys.kaz_kem_pk,
      });
      await get().loadFiles(get().currentFolder?.id ?? null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  deleteItem: async (itemId) => {
    try {
      await invoke('delete_item', { itemId });
      await get().loadFiles(get().currentFolder?.id ?? null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  renameItem: async (itemId, newName) => {
    try {
      await invoke('rename_item', { itemId, newName });
      await get().loadFiles(get().currentFolder?.id ?? null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  moveItem: async (itemId, newFolderId) => {
    try {
      await invoke('move_item', { itemId, newFolderId });
      await get().loadFiles(get().currentFolder?.id ?? null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ error: message });
      throw error;
    }
  },

  navigateToFolder: (folderId) => {
    get().loadFiles(folderId);
  },

  clearError: () => set({ error: null }),

  loadPreview: async (fileId) => {
    set({ isLoadingPreview: true, previewError: null });
    try {
      const preview = await invoke<FilePreview>('get_file_preview', { fileId });
      set({ previewFile: preview, isLoadingPreview: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      set({ previewError: message, isLoadingPreview: false });
    }
  },

  clearPreview: () => set({ previewFile: null, previewError: null }),

  dismissUpload: (uploadId) => {
    set((state) => {
      const newProgress = new Map(state.uploadProgress);
      newProgress.delete(uploadId);
      return { uploadProgress: newProgress };
    });
  },

  dismissDownload: (downloadId) => {
    set((state) => {
      const newProgress = new Map(state.downloadProgress);
      newProgress.delete(downloadId);
      return { downloadProgress: newProgress };
    });
  },

  setSearchQuery: (query) => set({ searchQuery: query }),

  setFilter: (key, value) =>
    set((state) => ({
      filters: { ...state.filters, [key]: value },
    })),

  clearFilters: () =>
    set({
      searchQuery: '',
      filters: { type: 'all', sharedStatus: 'all' },
    }),

  setSorting: (field) =>
    set((state) => ({
      sortBy: field,
      sortOrder: state.sortBy === field && state.sortOrder === 'asc' ? 'desc' : 'asc',
    })),

  setViewMode: (mode) => set({ viewMode: mode }),

  getFilteredItems: () => {
    const { items, searchQuery, filters, sortBy, sortOrder } = get();

    // Filter items
    const filtered = items.filter((item) => {
      // Search query filter (case-insensitive)
      if (searchQuery) {
        const query = searchQuery.toLowerCase();
        if (!item.name.toLowerCase().includes(query)) {
          return false;
        }
      }

      // Type filter
      if (filters.type !== 'all' && item.item_type !== filters.type) {
        return false;
      }

      // Shared status filter
      if (filters.sharedStatus !== 'all') {
        if (filters.sharedStatus === 'shared' && !item.is_shared) {
          return false;
        }
        if (filters.sharedStatus === 'not_shared' && (item.is_shared || item.is_received_share)) {
          return false;
        }
        if (filters.sharedStatus === 'received' && !item.is_received_share) {
          return false;
        }
      }

      return true;
    });

    // Sort items (folders first, then by selected field)
    filtered.sort((a, b) => {
      // Folders always come first
      if (a.item_type === 'folder' && b.item_type !== 'folder') return -1;
      if (a.item_type !== 'folder' && b.item_type === 'folder') return 1;

      // Then sort by selected field
      let comparison = 0;
      switch (sortBy) {
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
        case 'size':
          comparison = a.size - b.size;
          break;
        case 'updated_at':
          comparison = new Date(a.updated_at).getTime() - new Date(b.updated_at).getTime();
          break;
      }

      return sortOrder === 'asc' ? comparison : -comparison;
    });

    return filtered;
  },

  selectItem: (id) =>
    set({ selectedItems: new Set([id]) }),

  toggleSelection: (id) =>
    set((state) => {
      const newSelected = new Set(state.selectedItems);
      if (newSelected.has(id)) {
        newSelected.delete(id);
      } else {
        newSelected.add(id);
      }
      return { selectedItems: newSelected };
    }),

  selectAll: () =>
    set((state) => ({
      selectedItems: new Set(state.items.map((item) => item.id)),
    })),

  clearSelection: () =>
    set({ selectedItems: new Set() }),
}));
