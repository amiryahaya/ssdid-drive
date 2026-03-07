import { describe, it, expect } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { StatusBadge } from '../StatusBadge';

describe('StatusBadge', () => {
  it('should render pending status', () => {
    render(<StatusBadge status="pending" />);

    expect(screen.getByText('Pending')).toBeInTheDocument();
  });

  it('should render accepted status', () => {
    render(<StatusBadge status="accepted" />);

    expect(screen.getByText('Accepted')).toBeInTheDocument();
  });

  it('should render declined status', () => {
    render(<StatusBadge status="declined" />);

    expect(screen.getByText('Declined')).toBeInTheDocument();
  });

  it('should return null for unknown status', () => {
    const { container } = render(<StatusBadge status="unknown" />);

    expect(container.firstChild).toBeNull();
  });

  it('should apply pending styles', () => {
    render(<StatusBadge status="pending" />);

    const badge = screen.getByText('Pending');
    expect(badge).toHaveClass('bg-yellow-100');
  });

  it('should apply accepted styles', () => {
    render(<StatusBadge status="accepted" />);

    const badge = screen.getByText('Accepted');
    expect(badge).toHaveClass('bg-green-100');
  });

  it('should apply declined styles', () => {
    render(<StatusBadge status="declined" />);

    const badge = screen.getByText('Declined');
    expect(badge).toHaveClass('bg-red-100');
  });

  it('should apply custom className', () => {
    render(<StatusBadge status="pending" className="custom-class" />);

    const badge = screen.getByText('Pending');
    expect(badge).toHaveClass('custom-class');
  });
});
