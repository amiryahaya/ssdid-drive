import { create } from 'zustand';
import { tauriService } from '../services/tauri';
import type { Share, RecipientSearchResult, CreateShareRequest } from '../types';

interface ShareState {
  // Data
  myShares: Share[];
  sharedWithMe: Share[];
  itemShares: Share[];
  searchResults: RecipientSearchResult[];

  // Loading states
  isLoading: boolean;
  isSearching: boolean;
  isCreating: boolean;
  isUpdating: boolean;

  // Error state
  error: string | null;

  // Actions
  loadMyShares: () => Promise<void>;
  loadSharedWithMe: () => Promise<void>;
  loadSharesForItem: (itemId: string) => Promise<void>;
  searchRecipients: (query: string) => Promise<void>;
  createShare: (request: CreateShareRequest) => Promise<void>;
  revokeShare: (shareId: string) => Promise<void>;
  updateShare: (shareId: string, permission: string, expiresAt?: string) => Promise<void>;
  updatePermission: (shareId: string, permission: string) => Promise<void>;
  setExpiry: (shareId: string, expiresAt: string | null) => Promise<void>;
  acceptShare: (shareId: string) => Promise<void>;
  declineShare: (shareId: string) => Promise<void>;
  clearSearch: () => void;
  clearError: () => void;
}

export const useShareStore = create<ShareState>((set, get) => ({
  myShares: [],
  sharedWithMe: [],
  itemShares: [],
  searchResults: [],
  isLoading: false,
  isSearching: false,
  isCreating: false,
  isUpdating: false,
  error: null,

  loadMyShares: async () => {
    set({ isLoading: true, error: null });
    try {
      const response = await tauriService.listMyShares();
      set({ myShares: response.shares, isLoading: false });
    } catch (error) {
      set({ error: String(error), isLoading: false });
    }
  },

  loadSharedWithMe: async () => {
    set({ isLoading: true, error: null });
    try {
      const response = await tauriService.listSharedWithMe();
      set({ sharedWithMe: response.shares, isLoading: false });
    } catch (error) {
      set({ error: String(error), isLoading: false });
    }
  },

  loadSharesForItem: async (itemId: string) => {
    set({ isLoading: true, error: null });
    try {
      const response = await tauriService.getSharesForItem(itemId);
      set({ itemShares: response.shares, isLoading: false });
    } catch (error) {
      set({ error: String(error), isLoading: false });
    }
  },

  searchRecipients: async (query: string) => {
    if (query.length < 2) {
      set({ searchResults: [] });
      return;
    }
    set({ isSearching: true });
    try {
      const results = await tauriService.searchRecipients(query);
      set({ searchResults: results, isSearching: false });
    } catch (error) {
      set({ searchResults: [], isSearching: false });
    }
  },

  createShare: async (request: CreateShareRequest) => {
    set({ isCreating: true, error: null });
    try {
      await tauriService.createShare(request);
      // Reload shares to get updated list
      await get().loadMyShares();
      set({ isCreating: false });
    } catch (error) {
      set({ error: String(error), isCreating: false });
      throw error;
    }
  },

  revokeShare: async (shareId: string) => {
    set({ error: null });
    try {
      await tauriService.revokeShare(shareId);
      set((state) => ({
        myShares: state.myShares.filter((s) => s.id !== shareId),
        itemShares: state.itemShares.filter((s) => s.id !== shareId),
      }));
    } catch (error) {
      set({ error: String(error) });
      throw error;
    }
  },

  updateShare: async (shareId: string, permission: string, expiresAt?: string) => {
    set({ error: null });
    try {
      const updated = await tauriService.updateShare(shareId, permission, expiresAt);
      set((state) => ({
        myShares: state.myShares.map((s) => (s.id === shareId ? updated : s)),
        itemShares: state.itemShares.map((s) => (s.id === shareId ? updated : s)),
      }));
    } catch (error) {
      set({ error: String(error) });
      throw error;
    }
  },

  updatePermission: async (shareId: string, permission: string) => {
    set({ isUpdating: true, error: null });
    try {
      const updated = await tauriService.updateSharePermission(shareId, permission);
      set((state) => ({
        myShares: state.myShares.map((s) => (s.id === shareId ? updated : s)),
        itemShares: state.itemShares.map((s) => (s.id === shareId ? updated : s)),
        isUpdating: false,
      }));
    } catch (error) {
      set({ error: String(error), isUpdating: false });
      throw error;
    }
  },

  setExpiry: async (shareId: string, expiresAt: string | null) => {
    set({ isUpdating: true, error: null });
    try {
      const updated = await tauriService.setShareExpiry(shareId, expiresAt);
      set((state) => ({
        myShares: state.myShares.map((s) => (s.id === shareId ? updated : s)),
        itemShares: state.itemShares.map((s) => (s.id === shareId ? updated : s)),
        isUpdating: false,
      }));
    } catch (error) {
      set({ error: String(error), isUpdating: false });
      throw error;
    }
  },

  acceptShare: async (shareId: string) => {
    set({ error: null });
    try {
      const updated = await tauriService.acceptShare(shareId);
      set((state) => ({
        sharedWithMe: state.sharedWithMe.map((s) => (s.id === shareId ? updated : s)),
      }));
    } catch (error) {
      set({ error: String(error) });
      throw error;
    }
  },

  declineShare: async (shareId: string) => {
    set({ error: null });
    try {
      await tauriService.declineShare(shareId);
      set((state) => ({
        sharedWithMe: state.sharedWithMe.filter((s) => s.id !== shareId),
      }));
    } catch (error) {
      set({ error: String(error) });
      throw error;
    }
  },

  clearSearch: () => set({ searchResults: [] }),
  clearError: () => set({ error: null }),
}));
