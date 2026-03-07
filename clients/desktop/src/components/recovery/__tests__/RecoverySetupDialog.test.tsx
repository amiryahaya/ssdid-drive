import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../../test/utils';
import { RecoverySetupDialog } from '../RecoverySetupDialog';
import { useRecoveryStore, RecoverySetup } from '../../../stores/recoveryStore';
import { invoke } from '@tauri-apps/api/core';

vi.mock('@tauri-apps/api/core');

const mockInvoke = vi.mocked(invoke);

const mockExistingSetup: RecoverySetup = {
  id: 'setup-1',
  threshold: 2,
  total_trustees: 3,
  trustees: [
    {
      id: 'trustee-1',
      email: 'alice@example.com',
      name: 'Alice Smith',
      status: 'accepted',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-2',
      email: 'bob@example.com',
      name: 'Bob Jones',
      status: 'pending',
      added_at: '2024-01-15T10:00:00Z',
    },
    {
      id: 'trustee-3',
      email: 'carol@example.com',
      name: 'Carol White',
      status: 'pending',
      added_at: '2024-01-15T10:00:00Z',
    },
  ],
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-15T10:00:00Z',
};

describe('RecoverySetupDialog', () => {
  const mockOnOpenChange = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();

    useRecoveryStore.setState({
      setup: null,
      pendingRequests: [],
      isLoading: false,
      isSettingUp: false,
      error: null,
    });

    mockInvoke.mockResolvedValue(undefined);
  });

  describe('when creating new setup', () => {
    it('should render dialog title for new setup', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByText('Set Up Account Recovery')).toBeInTheDocument();
    });

    it('should render description text', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(
        screen.getByText(/choose trusted contacts who can help you recover/i)
      ).toBeInTheDocument();
    });

    it('should render Recovery Threshold section', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByText('Recovery Threshold')).toBeInTheDocument();
    });

    it('should render Trusted Contacts section', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByText('Trusted Contacts')).toBeInTheDocument();
    });

    it('should render two empty email inputs by default', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');
      expect(emailInputs).toHaveLength(2);
    });

    it('should render threshold select with default value 2', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const select = screen.getByRole('combobox');
      expect(select).toHaveValue('2');
    });

    it('should render Add Trustee button', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByRole('button', { name: /add trustee/i })).toBeInTheDocument();
    });

    it('should render Cancel button', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });

    it('should render Set Up Recovery submit button', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByRole('button', { name: /set up recovery/i })).toBeInTheDocument();
    });

    it('should render important warning', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByText('Important')).toBeInTheDocument();
      expect(
        screen.getByText(/only add people you trust completely/i)
      ).toBeInTheDocument();
    });

    it('should render minimum trustees message', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.getByText(/minimum 2 trustees required/i)).toBeInTheDocument();
    });
  });

  describe('when updating existing setup', () => {
    it('should render dialog title for update', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={mockExistingSetup}
        />
      );

      expect(screen.getByText('Update Recovery Setup')).toBeInTheDocument();
    });

    it('should render Update submit button', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={mockExistingSetup}
        />
      );

      expect(screen.getByRole('button', { name: /update/i })).toBeInTheDocument();
    });

    it('should populate email inputs with existing trustees', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={mockExistingSetup}
        />
      );

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');
      expect(emailInputs).toHaveLength(3);

      expect(emailInputs[0]).toHaveValue('alice@example.com');
      expect(emailInputs[1]).toHaveValue('bob@example.com');
      expect(emailInputs[2]).toHaveValue('carol@example.com');
    });

    it('should set threshold to existing value', () => {
      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={mockExistingSetup}
        />
      );

      const select = screen.getByRole('combobox');
      expect(select).toHaveValue('2');
    });
  });

  describe('interactions', () => {
    it('should add new email input when Add Trustee is clicked', async () => {
      const { user } = render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const addButton = screen.getByRole('button', { name: /add trustee/i });
      await user.click(addButton);

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');
      expect(emailInputs).toHaveLength(3);
    });

    it('should call onOpenChange with false when Cancel is clicked', async () => {
      const { user } = render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const cancelButton = screen.getByRole('button', { name: /cancel/i });
      await user.click(cancelButton);

      expect(mockOnOpenChange).toHaveBeenCalledWith(false);
    });

    it('should update email input value when typed', async () => {
      const { user } = render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');
      await user.type(emailInputs[0], 'test@example.com');

      expect(emailInputs[0]).toHaveValue('test@example.com');
    });

    it('should validate email format and show error for invalid email', async () => {
      const { user } = render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');
      await user.type(emailInputs[0], 'invalid-email');
      await user.type(emailInputs[1], 'test@example.com');

      const submitButton = screen.getByRole('button', { name: /set up recovery/i });
      await user.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Invalid email format')).toBeInTheDocument();
      });
    });

    it('should show error for empty email', async () => {
      const { user } = render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');
      await user.type(emailInputs[0], 'test@example.com');
      // Leave second email empty

      const submitButton = screen.getByRole('button', { name: /set up recovery/i });
      await user.click(submitButton);

      await waitFor(() => {
        expect(screen.getByText('Email is required')).toBeInTheDocument();
      });
    });

    it('should validate that each trustee email is unique', async () => {
      const { user } = render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');

      // Type the same email in both inputs
      await user.clear(emailInputs[0]);
      await user.type(emailInputs[0], 'same@example.com');
      await user.clear(emailInputs[1]);
      await user.type(emailInputs[1], 'same@example.com');

      // Submit the form
      const submitButton = screen.getByRole('button', { name: /set up recovery/i });
      await user.click(submitButton);

      // Wait for validation error
      await waitFor(() => {
        // The form should show a duplicate email error
        const errorElements = document.querySelectorAll('.text-destructive');
        expect(errorElements.length).toBeGreaterThan(0);
      });
    });

    it('should call setupRecovery when form is valid', async () => {
      const setupRecoverySpy = vi.fn().mockResolvedValue(undefined);
      useRecoveryStore.setState({
        setupRecovery: setupRecoverySpy,
      });

      const { user } = render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const emailInputs = screen.getAllByPlaceholderText('trustee@example.com');
      await user.type(emailInputs[0], 'alice@example.com');
      await user.type(emailInputs[1], 'bob@example.com');

      const submitButton = screen.getByRole('button', { name: /set up recovery/i });
      await user.click(submitButton);

      await waitFor(() => {
        expect(setupRecoverySpy).toHaveBeenCalledWith(2, [
          'alice@example.com',
          'bob@example.com',
        ]);
      });
    });
  });

  describe('loading state', () => {
    it('should show loading spinner when setting up', () => {
      useRecoveryStore.setState({ isSettingUp: true });

      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(document.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('should disable submit button when setting up', () => {
      useRecoveryStore.setState({ isSettingUp: true });

      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      const submitButton = screen.getByRole('button', { name: /set up recovery/i });
      expect(submitButton).toBeDisabled();
    });
  });

  describe('error state', () => {
    it('should clear error on dialog open', () => {
      const clearErrorSpy = vi.fn();
      useRecoveryStore.setState({
        error: 'Previous error',
        clearError: clearErrorSpy,
      });

      render(
        <RecoverySetupDialog
          open={true}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      // Dialog should clear error on open
      expect(clearErrorSpy).toHaveBeenCalled();
    });
  });

  describe('when closed', () => {
    it('should not render dialog content when closed', () => {
      render(
        <RecoverySetupDialog
          open={false}
          onOpenChange={mockOnOpenChange}
          existingSetup={null}
        />
      );

      expect(screen.queryByText('Set Up Account Recovery')).not.toBeInTheDocument();
    });
  });
});
