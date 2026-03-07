import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface FavoritesState {
  /** Set of favorite item IDs */
  favorites: Set<string>;

  /** Check if an item is favorited */
  isFavorite: (itemId: string) => boolean;

  /** Add item to favorites */
  addFavorite: (itemId: string) => void;

  /** Remove item from favorites */
  removeFavorite: (itemId: string) => void;

  /** Toggle favorite status */
  toggleFavorite: (itemId: string) => void;

  /** Get all favorite IDs as array */
  getFavoriteIds: () => string[];

  /** Clear all favorites */
  clearFavorites: () => void;
}

export const useFavoritesStore = create<FavoritesState>()(
  persist(
    (set, get) => ({
      favorites: new Set<string>(),

      isFavorite: (itemId) => get().favorites.has(itemId),

      addFavorite: (itemId) =>
        set((state) => ({
          favorites: new Set([...state.favorites, itemId]),
        })),

      removeFavorite: (itemId) =>
        set((state) => {
          const newFavorites = new Set(state.favorites);
          newFavorites.delete(itemId);
          return { favorites: newFavorites };
        }),

      toggleFavorite: (itemId) => {
        const { favorites } = get();
        if (favorites.has(itemId)) {
          get().removeFavorite(itemId);
        } else {
          get().addFavorite(itemId);
        }
      },

      getFavoriteIds: () => Array.from(get().favorites),

      clearFavorites: () => set({ favorites: new Set() }),
    }),
    {
      name: 'securesharing-favorites',
      // Custom serialization for Set
      storage: {
        getItem: (name) => {
          const str = localStorage.getItem(name);
          if (!str) return null;
          const parsed = JSON.parse(str);
          return {
            ...parsed,
            state: {
              ...parsed.state,
              favorites: new Set(parsed.state.favorites || []),
            },
          };
        },
        setItem: (name, value) => {
          const serialized = {
            ...value,
            state: {
              ...value.state,
              favorites: Array.from(value.state.favorites),
            },
          };
          localStorage.setItem(name, JSON.stringify(serialized));
        },
        removeItem: (name) => localStorage.removeItem(name),
      },
    }
  )
);
