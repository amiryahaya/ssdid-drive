import { describe, it, expect } from 'vitest';
import { render } from '../../../test/utils';
import { Skeleton, SkeletonText, SkeletonCircle, SkeletonButton } from '../Skeleton';

describe('Skeleton components', () => {
  describe('Skeleton', () => {
    it('should render with default styles', () => {
      const { container } = render(<Skeleton />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toBeInTheDocument();
      expect(skeleton).toHaveClass('animate-pulse');
      expect(skeleton).toHaveClass('rounded-md');
      expect(skeleton).toHaveClass('bg-muted');
    });

    it('should apply custom className', () => {
      const { container } = render(<Skeleton className="h-20 w-40" />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveClass('h-20');
      expect(skeleton).toHaveClass('w-40');
    });

    it('should be hidden from screen readers', () => {
      const { container } = render(<Skeleton />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveAttribute('aria-hidden', 'true');
    });
  });

  describe('SkeletonText', () => {
    it('should render with text-specific styles', () => {
      const { container } = render(<SkeletonText />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveClass('h-4');
      expect(skeleton).toHaveClass('w-full');
      expect(skeleton).toHaveClass('animate-pulse');
    });

    it('should apply custom className', () => {
      const { container } = render(<SkeletonText className="w-1/2" />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveClass('w-1/2');
    });
  });

  describe('SkeletonCircle', () => {
    it('should render with circle-specific styles', () => {
      const { container } = render(<SkeletonCircle />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveClass('h-10');
      expect(skeleton).toHaveClass('w-10');
      expect(skeleton).toHaveClass('rounded-full');
    });

    it('should apply custom className', () => {
      const { container } = render(<SkeletonCircle className="h-8 w-8" />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveClass('h-8');
      expect(skeleton).toHaveClass('w-8');
    });
  });

  describe('SkeletonButton', () => {
    it('should render with button-specific styles', () => {
      const { container } = render(<SkeletonButton />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveClass('h-9');
      expect(skeleton).toHaveClass('w-20');
      expect(skeleton).toHaveClass('rounded-md');
    });

    it('should apply custom className', () => {
      const { container } = render(<SkeletonButton className="w-32" />);

      const skeleton = container.firstChild as HTMLElement;
      expect(skeleton).toHaveClass('w-32');
    });
  });
});
