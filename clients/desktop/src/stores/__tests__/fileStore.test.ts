import { describe, it, expect, beforeEach, vi } from 'vitest';
import { useFileStore } from '../fileStore';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';

vi.mock('@tauri-apps/api/core');
vi.mock('@tauri-apps/api/event');

const mockInvoke = vi.mocked(invoke);
const mockListen = vi.mocked(listen);

// Mock file items
const mockFileItems = [
  {
    id: 'file-1',
    name: 'Document.pdf',
    item_type: 'file' as const,
    size: 1024 * 1024,
    mime_type: 'application/pdf',
    folder_id: null,
    owner_id: 'user-1',
    created_at: '2024-01-15T10:00:00Z',
    updated_at: '2024-01-15T10:00:00Z',
    is_shared: false,
    is_received_share: false,
  },
  {
    id: 'folder-1',
    name: 'Project Files',
    item_type: 'folder' as const,
    size: 0,
    mime_type: null,
    folder_id: null,
    owner_id: 'user-1',
    created_at: '2024-01-10T08:00:00Z',
    updated_at: '2024-01-10T08:00:00Z',
    is_shared: true,
    is_received_share: false,
  },
  {
    id: 'file-2',
    name: 'Shared.docx',
    item_type: 'file' as const,
    size: 2048,
    mime_type: 'application/docx',
    folder_id: null,
    owner_id: 'user-2',
    created_at: '2024-01-12T08:00:00Z',
    updated_at: '2024-01-14T08:00:00Z',
    is_shared: false,
    is_received_share: true,
  },
];

const mockFileListResponse = {
  items: mockFileItems,
  current_folder: null,
  breadcrumbs: [],
};

const mockFolderResponse = {
  items: [mockFileItems[0]],
  current_folder: { id: 'folder-1', name: 'Project Files', parent_id: null },
  breadcrumbs: [{ id: 'folder-1', name: 'Project Files', parent_id: null }],
};

const mockPreview = {
  file_id: 'file-1',
  file_name: 'Document.pdf',
  mime_type: 'application/pdf',
  preview_data: 'base64data',
  can_preview: true,
};

describe('fileStore', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset store to initial state
    useFileStore.setState({
      items: [],
      currentFolder: null,
      breadcrumbs: [],
      isLoading: false,
      error: null,
      uploadProgress: new Map(),
      downloadProgress: new Map(),
      searchQuery: '',
      filters: { type: 'all', sharedStatus: 'all' },
      sortBy: 'name',
      sortOrder: 'asc',
      viewMode: 'list',
      selectedItems: new Set(),
      previewFile: null,
      isLoadingPreview: false,
      previewError: null,
    });

    // Setup default mock for listen
    mockListen.mockResolvedValue(() => {});
  });

  describe('loadFiles', () => {
    it('should set loading state while loading', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockFileListResponse), 100))
      );

      const loadPromise = useFileStore.getState().loadFiles();

      expect(useFileStore.getState().isLoading).toBe(true);
      expect(useFileStore.getState().error).toBeNull();

      await loadPromise;
    });

    it('should load files successfully', async () => {
      mockInvoke.mockResolvedValueOnce(mockFileListResponse);

      await useFileStore.getState().loadFiles();

      expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: null });
      expect(useFileStore.getState().items).toEqual(mockFileItems);
      expect(useFileStore.getState().currentFolder).toBeNull();
      expect(useFileStore.getState().breadcrumbs).toEqual([]);
      expect(useFileStore.getState().isLoading).toBe(false);
    });

    it('should load files from a specific folder', async () => {
      mockInvoke.mockResolvedValueOnce(mockFolderResponse);

      await useFileStore.getState().loadFiles('folder-1');

      expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: 'folder-1' });
      expect(useFileStore.getState().currentFolder).toEqual({
        id: 'folder-1',
        name: 'Project Files',
        parent_id: null,
      });
      expect(useFileStore.getState().breadcrumbs).toHaveLength(1);
    });

    it('should set error on load failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Failed to load files'));

      await useFileStore.getState().loadFiles();

      expect(useFileStore.getState().error).toBe('Failed to load files');
      expect(useFileStore.getState().isLoading).toBe(false);
    });
  });

  describe('createFolder', () => {
    const mockKeys = { ml_kem_pk: 'ml-pk', kaz_kem_pk: 'kaz-pk' };

    it('should create folder and reload files', async () => {
      mockInvoke
        .mockResolvedValueOnce(mockKeys) // get_user_kem_public_keys
        .mockResolvedValueOnce(undefined) // create_folder
        .mockResolvedValueOnce(mockFileListResponse); // list_files

      await useFileStore.getState().createFolder('New Folder');

      expect(mockInvoke).toHaveBeenCalledWith('get_user_kem_public_keys');
      expect(mockInvoke).toHaveBeenCalledWith('create_folder', {
        name: 'New Folder',
        parentId: null,
        mlKemPk: 'ml-pk',
        kazKemPk: 'kaz-pk',
      });
      expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: null });
    });

    it('should create folder in specific parent', async () => {
      useFileStore.setState({
        currentFolder: { id: 'folder-1', name: 'Parent', parent_id: null },
      });

      mockInvoke
        .mockResolvedValueOnce(mockKeys) // get_user_kem_public_keys
        .mockResolvedValueOnce(undefined) // create_folder
        .mockResolvedValueOnce(mockFolderResponse); // list_files

      await useFileStore.getState().createFolder('Sub Folder', 'folder-1');

      expect(mockInvoke).toHaveBeenCalledWith('create_folder', {
        name: 'Sub Folder',
        parentId: 'folder-1',
        mlKemPk: 'ml-pk',
        kazKemPk: 'kaz-pk',
      });
    });

    it('should set error on create failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Folder already exists'));

      await expect(useFileStore.getState().createFolder('Test')).rejects.toThrow(
        'Folder already exists'
      );

      expect(useFileStore.getState().error).toBe('Folder already exists');
    });
  });

  describe('deleteItem', () => {
    it('should delete item and reload files', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // delete_item
        .mockResolvedValueOnce(mockFileListResponse); // list_files

      await useFileStore.getState().deleteItem('file-1');

      expect(mockInvoke).toHaveBeenCalledWith('delete_item', { itemId: 'file-1' });
      expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: null });
    });

    it('should set error on delete failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Permission denied'));

      await expect(useFileStore.getState().deleteItem('file-1')).rejects.toThrow(
        'Permission denied'
      );

      expect(useFileStore.getState().error).toBe('Permission denied');
    });
  });

  describe('renameItem', () => {
    it('should rename item and reload files', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // rename_item
        .mockResolvedValueOnce(mockFileListResponse); // list_files

      await useFileStore.getState().renameItem('file-1', 'NewName.pdf');

      expect(mockInvoke).toHaveBeenCalledWith('rename_item', {
        itemId: 'file-1',
        newName: 'NewName.pdf',
      });
    });

    it('should set error on rename failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Name already exists'));

      await expect(
        useFileStore.getState().renameItem('file-1', 'Duplicate.pdf')
      ).rejects.toThrow('Name already exists');

      expect(useFileStore.getState().error).toBe('Name already exists');
    });
  });

  describe('moveItem', () => {
    it('should move item and reload files', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // move_item
        .mockResolvedValueOnce(mockFileListResponse); // list_files

      await useFileStore.getState().moveItem('file-1', 'folder-2');

      expect(mockInvoke).toHaveBeenCalledWith('move_item', {
        itemId: 'file-1',
        newFolderId: 'folder-2',
      });
    });
  });

  describe('uploadFile', () => {
    it('should upload file with progress tracking', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined) // upload_file
        .mockResolvedValueOnce(mockFileListResponse); // list_files

      await useFileStore.getState().uploadFile('/path/to/file.pdf');

      expect(mockInvoke).toHaveBeenCalledWith('upload_file', {
        filePath: '/path/to/file.pdf',
        folderId: null,
        fileName: null,
      });
      expect(mockListen).toHaveBeenCalledWith('upload-progress', expect.any(Function));
    });

    it('should upload file to specific folder', async () => {
      mockInvoke
        .mockResolvedValueOnce(undefined)
        .mockResolvedValueOnce(mockFileListResponse);

      await useFileStore.getState().uploadFile('/path/to/file.pdf', 'folder-1');

      expect(mockInvoke).toHaveBeenCalledWith('upload_file', {
        filePath: '/path/to/file.pdf',
        folderId: 'folder-1',
        fileName: null,
      });
    });

    it('should set error on upload failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Upload failed'));

      await expect(
        useFileStore.getState().uploadFile('/path/to/file.pdf')
      ).rejects.toThrow('Upload failed');

      expect(useFileStore.getState().error).toBe('Upload failed');
    });
  });

  describe('downloadFile', () => {
    it('should download file with progress tracking', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);

      await useFileStore.getState().downloadFile('file-1', '/path/to/dest', 'Document.pdf');

      expect(mockInvoke).toHaveBeenCalledWith('download_file', {
        fileId: 'file-1',
        destination: '/path/to/dest',
      });
      expect(mockListen).toHaveBeenCalledWith('download-progress', expect.any(Function));
    });

    it('should initialize download progress', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(undefined), 50))
      );

      const downloadPromise = useFileStore
        .getState()
        .downloadFile('file-1', '/path/to/dest', 'Document.pdf');

      // Check that progress was initialized
      const progress = Array.from(useFileStore.getState().downloadProgress.values())[0];
      expect(progress).toBeDefined();
      expect(progress?.phase).toBe('preparing');
      expect(progress?.file_name).toBe('Document.pdf');

      await downloadPromise;
    });

    it('should set error on download failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Download failed'));

      await expect(
        useFileStore.getState().downloadFile('file-1', '/path', 'file.pdf')
      ).rejects.toThrow('Download failed');

      expect(useFileStore.getState().error).toBe('Download failed');
    });
  });

  describe('preview', () => {
    it('should load preview successfully', async () => {
      mockInvoke.mockResolvedValueOnce(mockPreview);

      await useFileStore.getState().loadPreview('file-1');

      expect(mockInvoke).toHaveBeenCalledWith('get_file_preview', { fileId: 'file-1' });
      expect(useFileStore.getState().previewFile).toEqual(mockPreview);
      expect(useFileStore.getState().isLoadingPreview).toBe(false);
    });

    it('should set loading state while loading preview', async () => {
      mockInvoke.mockImplementation(
        () => new Promise((resolve) => setTimeout(() => resolve(mockPreview), 100))
      );

      const loadPromise = useFileStore.getState().loadPreview('file-1');

      expect(useFileStore.getState().isLoadingPreview).toBe(true);

      await loadPromise;
    });

    it('should set error on preview failure', async () => {
      mockInvoke.mockRejectedValueOnce(new Error('Preview not available'));

      await useFileStore.getState().loadPreview('file-1');

      expect(useFileStore.getState().previewError).toBe('Preview not available');
      expect(useFileStore.getState().isLoadingPreview).toBe(false);
    });

    it('should clear preview', () => {
      useFileStore.setState({
        previewFile: mockPreview,
        previewError: 'Some error',
      });

      useFileStore.getState().clearPreview();

      expect(useFileStore.getState().previewFile).toBeNull();
      expect(useFileStore.getState().previewError).toBeNull();
    });
  });

  describe('progress management', () => {
    it('should dismiss upload progress', () => {
      useFileStore.setState({
        uploadProgress: new Map([
          ['upload-1', { file_id: 'f1', file_name: 'test.pdf', phase: 'complete', bytes_uploaded: 100, total_bytes: 100, progress_percent: 100 }],
        ]),
      });

      useFileStore.getState().dismissUpload('upload-1');

      expect(useFileStore.getState().uploadProgress.size).toBe(0);
    });

    it('should dismiss download progress', () => {
      useFileStore.setState({
        downloadProgress: new Map([
          ['download-1', { file_id: 'f1', file_name: 'test.pdf', phase: 'complete', bytes_downloaded: 100, total_bytes: 100, progress_percent: 100 }],
        ]),
      });

      useFileStore.getState().dismissDownload('download-1');

      expect(useFileStore.getState().downloadProgress.size).toBe(0);
    });
  });

  describe('search and filters', () => {
    beforeEach(() => {
      useFileStore.setState({ items: mockFileItems });
    });

    it('should set search query', () => {
      useFileStore.getState().setSearchQuery('document');

      expect(useFileStore.getState().searchQuery).toBe('document');
    });

    it('should filter items by search query', () => {
      useFileStore.getState().setSearchQuery('document');

      const filtered = useFileStore.getState().getFilteredItems();

      expect(filtered).toHaveLength(1);
      expect(filtered[0].name).toBe('Document.pdf');
    });

    it('should filter by type', () => {
      useFileStore.getState().setFilter('type', 'folder');

      const filtered = useFileStore.getState().getFilteredItems();

      expect(filtered).toHaveLength(1);
      expect(filtered[0].item_type).toBe('folder');
    });

    it('should filter by shared status', () => {
      useFileStore.getState().setFilter('sharedStatus', 'shared');

      const filtered = useFileStore.getState().getFilteredItems();

      expect(filtered).toHaveLength(1);
      expect(filtered[0].is_shared).toBe(true);
    });

    it('should filter by received status', () => {
      useFileStore.getState().setFilter('sharedStatus', 'received');

      const filtered = useFileStore.getState().getFilteredItems();

      expect(filtered).toHaveLength(1);
      expect(filtered[0].is_received_share).toBe(true);
    });

    it('should filter by not shared status', () => {
      useFileStore.getState().setFilter('sharedStatus', 'not_shared');

      const filtered = useFileStore.getState().getFilteredItems();

      expect(filtered).toHaveLength(1);
      expect(filtered[0].name).toBe('Document.pdf');
    });

    it('should clear filters', () => {
      useFileStore.getState().setSearchQuery('test');
      useFileStore.getState().setFilter('type', 'file');

      useFileStore.getState().clearFilters();

      expect(useFileStore.getState().searchQuery).toBe('');
      expect(useFileStore.getState().filters.type).toBe('all');
    });
  });

  describe('sorting', () => {
    beforeEach(() => {
      useFileStore.setState({ items: mockFileItems });
    });

    it('should sort by name ascending by default', () => {
      const filtered = useFileStore.getState().getFilteredItems();

      // Folders first, then files by name
      expect(filtered[0].name).toBe('Project Files'); // folder
      expect(filtered[1].name).toBe('Document.pdf'); // file
    });

    it('should toggle sort order on same field', () => {
      useFileStore.getState().setSorting('name');

      expect(useFileStore.getState().sortOrder).toBe('desc');

      useFileStore.getState().setSorting('name');

      expect(useFileStore.getState().sortOrder).toBe('asc');
    });

    it('should reset to ascending when changing field', () => {
      useFileStore.getState().setSorting('name'); // now desc
      useFileStore.getState().setSorting('size');

      expect(useFileStore.getState().sortBy).toBe('size');
      expect(useFileStore.getState().sortOrder).toBe('asc');
    });

    it('should sort by size', () => {
      useFileStore.getState().setSorting('size');

      const filtered = useFileStore.getState().getFilteredItems();

      // Folders first (size 0), then files by size ascending
      expect(filtered[0].item_type).toBe('folder');
    });

    it('should sort by updated_at', () => {
      useFileStore.getState().setSorting('updated_at');

      const filtered = useFileStore.getState().getFilteredItems();

      expect(filtered[0].item_type).toBe('folder'); // folders first
    });
  });

  describe('selection', () => {
    beforeEach(() => {
      useFileStore.setState({ items: mockFileItems });
    });

    it('should select single item', () => {
      useFileStore.getState().selectItem('file-1');

      expect(useFileStore.getState().selectedItems.has('file-1')).toBe(true);
      expect(useFileStore.getState().selectedItems.size).toBe(1);
    });

    it('should toggle selection', () => {
      useFileStore.getState().toggleSelection('file-1');
      expect(useFileStore.getState().selectedItems.has('file-1')).toBe(true);

      useFileStore.getState().toggleSelection('file-1');
      expect(useFileStore.getState().selectedItems.has('file-1')).toBe(false);
    });

    it('should add to selection with toggle', () => {
      useFileStore.getState().toggleSelection('file-1');
      useFileStore.getState().toggleSelection('file-2');

      expect(useFileStore.getState().selectedItems.size).toBe(2);
    });

    it('should select all items', () => {
      useFileStore.getState().selectAll();

      expect(useFileStore.getState().selectedItems.size).toBe(3);
      expect(useFileStore.getState().selectedItems.has('file-1')).toBe(true);
      expect(useFileStore.getState().selectedItems.has('folder-1')).toBe(true);
      expect(useFileStore.getState().selectedItems.has('file-2')).toBe(true);
    });

    it('should clear selection', () => {
      useFileStore.getState().selectAll();
      useFileStore.getState().clearSelection();

      expect(useFileStore.getState().selectedItems.size).toBe(0);
    });
  });

  describe('view mode', () => {
    it('should set view mode to grid', () => {
      useFileStore.getState().setViewMode('grid');

      expect(useFileStore.getState().viewMode).toBe('grid');
    });

    it('should set view mode to list', () => {
      useFileStore.setState({ viewMode: 'grid' });
      useFileStore.getState().setViewMode('list');

      expect(useFileStore.getState().viewMode).toBe('list');
    });
  });

  describe('clearError', () => {
    it('should clear error state', () => {
      useFileStore.setState({ error: 'Some error' });

      useFileStore.getState().clearError();

      expect(useFileStore.getState().error).toBeNull();
    });
  });

  describe('navigateToFolder', () => {
    it('should call loadFiles with folder id', async () => {
      mockInvoke.mockResolvedValueOnce(mockFolderResponse);

      useFileStore.getState().navigateToFolder('folder-1');

      // Wait for async loadFiles
      await vi.waitFor(() => {
        expect(mockInvoke).toHaveBeenCalledWith('list_files', { folderId: 'folder-1' });
      });
    });
  });
});
