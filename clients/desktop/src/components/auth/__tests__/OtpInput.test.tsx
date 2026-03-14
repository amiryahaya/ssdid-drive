import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen } from '@testing-library/react';
import { render } from '../../../test/utils';
import { OtpInput } from '../OtpInput';

describe('OtpInput', () => {
  const mockOnComplete = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders 6 inputs by default', () => {
    render(<OtpInput onComplete={mockOnComplete} />);
    const inputs = screen.getAllByRole('textbox');
    expect(inputs).toHaveLength(6);
  });

  it('renders custom number of inputs when length prop set', () => {
    render(<OtpInput onComplete={mockOnComplete} length={4} />);
    const inputs = screen.getAllByRole('textbox');
    expect(inputs).toHaveLength(4);
  });

  it('calls onComplete with full code when all digits entered', async () => {
    const { user } = render(<OtpInput onComplete={mockOnComplete} />);

    const inputs = screen.getAllByRole('textbox');
    await user.click(inputs[0]);
    await user.keyboard('1');
    await user.keyboard('2');
    await user.keyboard('3');
    await user.keyboard('4');
    await user.keyboard('5');
    await user.keyboard('6');

    expect(mockOnComplete).toHaveBeenCalledWith('123456');
  });

  it('does not call onComplete when not all digits entered', async () => {
    const { user } = render(<OtpInput onComplete={mockOnComplete} />);

    const inputs = screen.getAllByRole('textbox');
    await user.click(inputs[0]);
    await user.keyboard('1');
    await user.keyboard('2');
    await user.keyboard('3');

    expect(mockOnComplete).not.toHaveBeenCalled();
  });

  it('backspace on empty input focuses previous', async () => {
    const { user } = render(<OtpInput onComplete={mockOnComplete} />);

    const inputs = screen.getAllByRole('textbox');
    await user.click(inputs[0]);
    await user.keyboard('1');
    await user.keyboard('2');

    // Now focused on input[2], clear it and press backspace to go back to input[1]
    // input[2] is empty, so backspace should move focus to input[1]
    await user.keyboard('{Backspace}');

    expect(inputs[1]).toHaveFocus();
  });

  it('paste fills all inputs and calls onComplete', async () => {
    const { user } = render(<OtpInput onComplete={mockOnComplete} />);

    const inputs = screen.getAllByRole('textbox');
    await user.click(inputs[0]);
    await user.paste('123456');

    expect(mockOnComplete).toHaveBeenCalledWith('123456');
    expect(inputs[0]).toHaveValue('1');
    expect(inputs[1]).toHaveValue('2');
    expect(inputs[2]).toHaveValue('3');
    expect(inputs[3]).toHaveValue('4');
    expect(inputs[4]).toHaveValue('5');
    expect(inputs[5]).toHaveValue('6');
  });

  it('paste with partial code focuses next empty input', async () => {
    const { user } = render(<OtpInput onComplete={mockOnComplete} />);

    const inputs = screen.getAllByRole('textbox');
    await user.click(inputs[0]);
    await user.paste('123');

    expect(mockOnComplete).not.toHaveBeenCalled();
    expect(inputs[0]).toHaveValue('1');
    expect(inputs[1]).toHaveValue('2');
    expect(inputs[2]).toHaveValue('3');
    expect(inputs[3]).toHaveFocus();
  });

  it('shows error message when error prop provided', () => {
    render(<OtpInput onComplete={mockOnComplete} error="Invalid code" />);
    expect(screen.getByText('Invalid code')).toBeInTheDocument();
  });

  it('resets inputs on error change', async () => {
    const { user, rerender } = render(
      <OtpInput onComplete={mockOnComplete} />
    );

    const inputs = screen.getAllByRole('textbox');
    await user.click(inputs[0]);
    await user.keyboard('1');
    await user.keyboard('2');
    await user.keyboard('3');

    // Trigger error change
    rerender(<OtpInput onComplete={mockOnComplete} error="Wrong code" />);

    const updatedInputs = screen.getAllByRole('textbox');
    for (const input of updatedInputs) {
      expect(input).toHaveValue('');
    }
  });

  it('disables all inputs when disabled=true', () => {
    render(<OtpInput onComplete={mockOnComplete} disabled />);

    const inputs = screen.getAllByRole('textbox');
    for (const input of inputs) {
      expect(input).toBeDisabled();
    }
  });
});
