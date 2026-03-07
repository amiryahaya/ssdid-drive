import { describe, it, expect, beforeEach } from 'vitest';
import { useFavoritesStore } from '../favoritesStore';

describe('favoritesStore', () => {
  beforeEach(() => {
    useFavoritesStore.setState({ favorites: new Set<string>() });
  });

  describe('initial state', () => {
    it('should start with empty favorites', () => {
      const state = useFavoritesStore.getState();
      expect(state.favorites.size).toBe(0);
    });

    it('should return empty array from getFavoriteIds', () => {
      const ids = useFavoritesStore.getState().getFavoriteIds();
      expect(ids).toEqual([]);
    });
  });

  describe('addFavorite', () => {
    it('should add an item to favorites', () => {
      useFavoritesStore.getState().addFavorite('file-1');
      expect(useFavoritesStore.getState().isFavorite('file-1')).toBe(true);
    });

    it('should not duplicate items', () => {
      const { addFavorite } = useFavoritesStore.getState();
      addFavorite('file-1');
      addFavorite('file-1');
      expect(useFavoritesStore.getState().favorites.size).toBe(1);
    });
  });

  describe('removeFavorite', () => {
    it('should remove an item from favorites', () => {
      useFavoritesStore.getState().addFavorite('file-1');
      useFavoritesStore.getState().removeFavorite('file-1');
      expect(useFavoritesStore.getState().isFavorite('file-1')).toBe(false);
    });

    it('should not throw when removing non-existent item', () => {
      expect(() => useFavoritesStore.getState().removeFavorite('nonexistent')).not.toThrow();
    });
  });

  describe('toggleFavorite', () => {
    it('should add item when not favorited', () => {
      useFavoritesStore.getState().toggleFavorite('file-1');
      expect(useFavoritesStore.getState().isFavorite('file-1')).toBe(true);
    });

    it('should remove item when already favorited', () => {
      useFavoritesStore.getState().addFavorite('file-1');
      useFavoritesStore.getState().toggleFavorite('file-1');
      expect(useFavoritesStore.getState().isFavorite('file-1')).toBe(false);
    });
  });

  describe('getFavoriteIds', () => {
    it('should return all favorite IDs as array', () => {
      const { addFavorite } = useFavoritesStore.getState();
      addFavorite('file-1');
      addFavorite('file-2');
      addFavorite('file-3');

      const ids = useFavoritesStore.getState().getFavoriteIds();
      expect(ids).toHaveLength(3);
      expect(ids).toContain('file-1');
      expect(ids).toContain('file-2');
      expect(ids).toContain('file-3');
    });
  });

  describe('clearFavorites', () => {
    it('should remove all favorites', () => {
      const { addFavorite } = useFavoritesStore.getState();
      addFavorite('file-1');
      addFavorite('file-2');

      useFavoritesStore.getState().clearFavorites();
      expect(useFavoritesStore.getState().favorites.size).toBe(0);
    });
  });

  describe('isFavorite', () => {
    it('should return false for non-favorited item', () => {
      expect(useFavoritesStore.getState().isFavorite('unknown')).toBe(false);
    });

    it('should return true for favorited item', () => {
      useFavoritesStore.getState().addFavorite('file-1');
      expect(useFavoritesStore.getState().isFavorite('file-1')).toBe(true);
    });
  });
});
