import { describe, it, expect } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { DropZoneOverlay } from '../DropZoneOverlay';

describe('DropZoneOverlay', () => {
  describe('visibility', () => {
    it('should not render when isVisible is false', () => {
      const { container } = render(<DropZoneOverlay isVisible={false} />);
      expect(container).toBeEmptyDOMElement();
    });

    it('should render when isVisible is true', () => {
      render(<DropZoneOverlay isVisible={true} />);
      expect(screen.getByText('Drop files to upload')).toBeInTheDocument();
    });
  });

  describe('content', () => {
    it('should display the title', () => {
      render(<DropZoneOverlay isVisible={true} />);
      expect(screen.getByRole('heading', { name: /drop files to upload/i })).toBeInTheDocument();
    });

    it('should display the instruction text', () => {
      render(<DropZoneOverlay isVisible={true} />);
      expect(screen.getByText('Release to start uploading your files')).toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('should have fixed positioning', () => {
      render(<DropZoneOverlay isVisible={true} />);
      const overlay = screen.getByText('Drop files to upload').closest('.fixed');
      expect(overlay).toBeInTheDocument();
    });

    it('should have a high z-index (z-50)', () => {
      render(<DropZoneOverlay isVisible={true} />);
      const overlay = screen.getByText('Drop files to upload').closest('.z-50');
      expect(overlay).toBeInTheDocument();
    });
  });

  describe('transitions', () => {
    it('should show overlay immediately when isVisible changes to true', () => {
      const { rerender } = render(<DropZoneOverlay isVisible={false} />);

      rerender(<DropZoneOverlay isVisible={true} />);

      expect(screen.getByText('Drop files to upload')).toBeInTheDocument();
    });

    it('should hide overlay immediately when isVisible changes to false', () => {
      const { rerender, container } = render(<DropZoneOverlay isVisible={true} />);

      rerender(<DropZoneOverlay isVisible={false} />);

      expect(container).toBeEmptyDOMElement();
    });
  });
});
