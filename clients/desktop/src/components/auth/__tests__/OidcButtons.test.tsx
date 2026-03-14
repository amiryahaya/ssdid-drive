import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { OidcButtons } from '../OidcButtons';

describe('OidcButtons', () => {
  const mockOnProviderClick = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders both Google and Microsoft buttons', () => {
    render(<OidcButtons onProviderClick={mockOnProviderClick} />);

    expect(screen.getByText('Continue with Google')).toBeInTheDocument();
    expect(screen.getByText('Continue with Microsoft')).toBeInTheDocument();
  });

  it("calls onProviderClick('google') on Google click", async () => {
    const { user } = render(<OidcButtons onProviderClick={mockOnProviderClick} />);

    await user.click(screen.getByText('Continue with Google'));

    expect(mockOnProviderClick).toHaveBeenCalledWith('google');
  });

  it("calls onProviderClick('microsoft') on Microsoft click", async () => {
    const { user } = render(<OidcButtons onProviderClick={mockOnProviderClick} />);

    await user.click(screen.getByText('Continue with Microsoft'));

    expect(mockOnProviderClick).toHaveBeenCalledWith('microsoft');
  });

  it('disables both when disabled=true', () => {
    render(<OidcButtons onProviderClick={mockOnProviderClick} disabled />);

    const googleButton = screen.getByText('Continue with Google').closest('button')!;
    const microsoftButton = screen.getByText('Continue with Microsoft').closest('button')!;

    expect(googleButton).toBeDisabled();
    expect(microsoftButton).toBeDisabled();
  });

  it("disables both when loading='google' (any loading state)", () => {
    render(<OidcButtons onProviderClick={mockOnProviderClick} loading="google" />);

    const googleButton = screen.getByText('Continue with Google').closest('button')!;
    const microsoftButton = screen.getByText('Continue with Microsoft').closest('button')!;

    expect(googleButton).toBeDisabled();
    expect(microsoftButton).toBeDisabled();
  });

  it('Google button has no spinner by default', () => {
    render(<OidcButtons onProviderClick={mockOnProviderClick} />);

    const googleButton = screen.getByText('Continue with Google').closest('button')!;
    const spinner = googleButton.querySelector('.animate-spin');

    expect(spinner).not.toBeInTheDocument();
  });

  it("shows spinner on Google button when loading='google'", () => {
    render(<OidcButtons onProviderClick={mockOnProviderClick} loading="google" />);

    const googleButton = screen.getByText('Continue with Google').closest('button')!;
    const spinner = googleButton.querySelector('.animate-spin');

    expect(spinner).toBeInTheDocument();
  });

  it("shows spinner on Microsoft button when loading='microsoft'", () => {
    render(<OidcButtons onProviderClick={mockOnProviderClick} loading="microsoft" />);

    const microsoftButton = screen.getByText('Continue with Microsoft').closest('button')!;
    const spinner = microsoftButton.querySelector('.animate-spin');

    expect(spinner).toBeInTheDocument();
  });
});
