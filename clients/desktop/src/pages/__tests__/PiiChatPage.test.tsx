import { describe, it, expect } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../test/utils';
import { PiiChatPage } from '../PiiChatPage';

describe('PiiChatPage', () => {
  it('should render coming soon message', () => {
    render(<PiiChatPage />);

    expect(screen.getByText('AI Chat')).toBeInTheDocument();
    expect(screen.getByText('Coming Soon')).toBeInTheDocument();
  });

  it('should show feature description', () => {
    render(<PiiChatPage />);

    expect(
      screen.getByText(/Secure AI conversations with automatic PII redaction/)
    ).toBeInTheDocument();
  });

  it('should show encryption info', () => {
    render(<PiiChatPage />);

    expect(screen.getByText(/End-to-end encrypted with ML-KEM/)).toBeInTheDocument();
  });
});
