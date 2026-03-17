import { describe, it, expect, vi, beforeEach } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import { render } from '../../test/utils';
import { RecoveryPage } from '../RecoveryPage';

// Mock react-router-dom
const mockNavigate = vi.fn();
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => mockNavigate,
  };
});

// Mock Tauri dialog
const mockOpen = vi.fn();
vi.mock('@tauri-apps/plugin-dialog', () => ({
  open: (...args: unknown[]) => mockOpen(...args),
}));

// Mock Tauri fs
const mockReadTextFile = vi.fn();
vi.mock('@tauri-apps/plugin-fs', () => ({
  readTextFile: (...args: unknown[]) => mockReadTextFile(...args),
}));

// Mock tauriService
const mockRecoverWithFiles = vi.fn();
const mockRecoverWithFileAndServer = vi.fn();
vi.mock('@/services/tauri', () => ({
  tauriService: {
    recoverWithFiles: (...args: unknown[]) => mockRecoverWithFiles(...args),
    recoverWithFileAndServer: (...args: unknown[]) => mockRecoverWithFileAndServer(...args),
  },
}));

const mockRecoveryFileContents = JSON.stringify({
  share_index: 1,
  user_did: 'did:example:user1',
  share_data: 'encrypted-share-data-1',
});

const mockRecoveryFile2Contents = JSON.stringify({
  share_index: 2,
  user_did: 'did:example:user1',
  share_data: 'encrypted-share-data-2',
});

describe('RecoveryPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRecoverWithFiles.mockResolvedValue({ success: true });
    mockRecoverWithFileAndServer.mockResolvedValue({ success: true });
  });

  it('should render page title', () => {
    render(<RecoveryPage />);

    expect(screen.getByRole('heading', { name: 'Recover Account' })).toBeInTheDocument();
  });

  it('should render page description', () => {
    render(<RecoveryPage />);

    expect(
      screen.getByText('Restore access to your SSDID Drive account')
    ).toBeInTheDocument();
  });

  it('should render back to login link', () => {
    render(<RecoveryPage />);

    const backLink = screen.getByText('Back to login');
    expect(backLink).toBeInTheDocument();
    expect(backLink.closest('a')).toHaveAttribute('href', '/login');
  });

  describe('path selection', () => {
    it('should show recovery method options', () => {
      render(<RecoveryPage />);

      expect(
        screen.getByText('How would you like to recover your account?')
      ).toBeInTheDocument();
      expect(
        screen.getByText('I have 2 recovery files')
      ).toBeInTheDocument();
      expect(
        screen.getByText('I have 1 recovery file + server share')
      ).toBeInTheDocument();
    });

    it('should show two-files flow when first option is clicked', async () => {
      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      expect(screen.getByText('First recovery file')).toBeInTheDocument();
      expect(screen.getByText('Second recovery file')).toBeInTheDocument();
      expect(
        screen.getByText('Choose a different recovery method')
      ).toBeInTheDocument();
    });

    it('should show file-and-server flow when second option is clicked', async () => {
      const { user } = render(<RecoveryPage />);

      await user.click(
        screen.getByText('I have 1 recovery file + server share')
      );

      expect(screen.getByText('Recovery file')).toBeInTheDocument();
      expect(
        screen.getByText(
          'The server will provide the second share automatically.'
        )
      ).toBeInTheDocument();
    });

    it('should go back to path selection when reset is clicked', async () => {
      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));
      expect(screen.getByText('First recovery file')).toBeInTheDocument();

      await user.click(
        screen.getByText('Choose a different recovery method')
      );

      expect(
        screen.getByText('How would you like to recover your account?')
      ).toBeInTheDocument();
    });
  });

  describe('two-files recovery flow', () => {
    it('should disable Recover Account button when no files selected', async () => {
      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      const recoverButton = screen.getByRole('button', { name: 'Recover Account' });
      expect(recoverButton).toBeDisabled();
    });

    it('should pick a recovery file when upload slot is clicked', async () => {
      mockOpen.mockResolvedValue('/path/to/recovery1.recovery');
      mockReadTextFile.mockResolvedValue(mockRecoveryFileContents);

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      // Click the first upload slot
      const firstSlot = screen.getByText('First recovery file')
        .closest('div')!
        .querySelector('button')!;
      await user.click(firstSlot);

      expect(mockOpen).toHaveBeenCalledWith({
        filters: [{ name: 'Recovery File', extensions: ['recovery'] }],
        multiple: false,
      });

      await waitFor(() => {
        expect(screen.getByText('recovery1.recovery')).toBeInTheDocument();
      });
    });

    it('should show error when file reading fails', async () => {
      mockOpen.mockResolvedValue('/path/to/recovery1.recovery');
      mockReadTextFile.mockRejectedValue(new Error('File not found'));

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      const firstSlot = screen.getByText('First recovery file')
        .closest('div')!
        .querySelector('button')!;
      await user.click(firstSlot);

      await waitFor(() => {
        expect(
          screen.getByText(/Failed to read recovery file/)
        ).toBeInTheDocument();
      });
    });

    it('should show error when both files have the same share index', async () => {
      const sameIndexContents = JSON.stringify({
        share_index: 1,
        user_did: 'did:example:user1',
      });

      mockOpen.mockResolvedValue('/path/to/file.recovery');
      mockReadTextFile.mockResolvedValue(sameIndexContents);

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      // Pick both files with same index
      const slots = screen.getAllByText('Click to select .recovery file');
      await user.click(slots[0]);
      await waitFor(() => {
        expect(mockOpen).toHaveBeenCalledTimes(1);
      });

      await user.click(slots.length > 1 ? slots[1] : screen.getByText('Click to select .recovery file'));
      await waitFor(() => {
        expect(mockOpen).toHaveBeenCalledTimes(2);
      });

      // Now try to recover
      const recoverButton = screen.getByRole('button', { name: 'Recover Account' });
      await user.click(recoverButton);

      await waitFor(() => {
        expect(
          screen.getByText(
            'Both files have the same share index. Please upload two different recovery files.'
          )
        ).toBeInTheDocument();
      });
    });

    it('should call recoverWithFiles on successful submission', async () => {
      // First file pick
      mockOpen
        .mockResolvedValueOnce('/path/to/recovery1.recovery')
        .mockResolvedValueOnce('/path/to/recovery2.recovery');
      mockReadTextFile
        .mockResolvedValueOnce(mockRecoveryFileContents)
        .mockResolvedValueOnce(mockRecoveryFile2Contents);

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      // Pick first file
      const uploadSlots = screen.getAllByText('Click to select .recovery file');
      await user.click(uploadSlots[0]);
      await waitFor(() => {
        expect(screen.getByText('recovery1.recovery')).toBeInTheDocument();
      });

      // Pick second file
      await user.click(screen.getByText('Click to select .recovery file'));
      await waitFor(() => {
        expect(screen.getByText('recovery2.recovery')).toBeInTheDocument();
      });

      // Click recover
      await user.click(screen.getByRole('button', { name: 'Recover Account' }));

      await waitFor(() => {
        expect(mockRecoverWithFiles).toHaveBeenCalledWith(
          mockRecoveryFileContents,
          mockRecoveryFile2Contents
        );
      });
    });

    it('should show success state after recovery', async () => {
      mockOpen
        .mockResolvedValueOnce('/path/to/recovery1.recovery')
        .mockResolvedValueOnce('/path/to/recovery2.recovery');
      mockReadTextFile
        .mockResolvedValueOnce(mockRecoveryFileContents)
        .mockResolvedValueOnce(mockRecoveryFile2Contents);

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      // Pick both files
      const uploadSlots = screen.getAllByText('Click to select .recovery file');
      await user.click(uploadSlots[0]);
      await waitFor(() => {
        expect(screen.getByText('recovery1.recovery')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Click to select .recovery file'));
      await waitFor(() => {
        expect(screen.getByText('recovery2.recovery')).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: 'Recover Account' }));

      await waitFor(() => {
        expect(screen.getByText('Account Recovered')).toBeInTheDocument();
        expect(
          screen.getByText(/Your account has been successfully recovered/)
        ).toBeInTheDocument();
      });
    });

    it('should show error when recovery fails', async () => {
      mockRecoverWithFiles.mockRejectedValue(new Error('Server unavailable'));

      mockOpen
        .mockResolvedValueOnce('/path/to/recovery1.recovery')
        .mockResolvedValueOnce('/path/to/recovery2.recovery');
      mockReadTextFile
        .mockResolvedValueOnce(mockRecoveryFileContents)
        .mockResolvedValueOnce(mockRecoveryFile2Contents);

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      const uploadSlots = screen.getAllByText('Click to select .recovery file');
      await user.click(uploadSlots[0]);
      await waitFor(() => {
        expect(screen.getByText('recovery1.recovery')).toBeInTheDocument();
      });

      await user.click(screen.getByText('Click to select .recovery file'));
      await waitFor(() => {
        expect(screen.getByText('recovery2.recovery')).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: 'Recover Account' }));

      await waitFor(() => {
        expect(
          screen.getByText(/Recovery failed: Server unavailable/)
        ).toBeInTheDocument();
      });
    });
  });

  describe('file-and-server recovery flow', () => {
    it('should disable Recover Account button when no file selected', async () => {
      const { user } = render(<RecoveryPage />);

      await user.click(
        screen.getByText('I have 1 recovery file + server share')
      );

      const recoverButton = screen.getByRole('button', { name: 'Recover Account' });
      expect(recoverButton).toBeDisabled();
    });

    it('should call recoverWithFileAndServer on submission', async () => {
      mockOpen.mockResolvedValue('/path/to/recovery.recovery');
      mockReadTextFile.mockResolvedValue(mockRecoveryFileContents);

      const { user } = render(<RecoveryPage />);

      await user.click(
        screen.getByText('I have 1 recovery file + server share')
      );

      // Pick file
      const uploadSlot = screen.getByText('Click to select .recovery file');
      await user.click(uploadSlot);

      await waitFor(() => {
        expect(screen.getByText('recovery.recovery')).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: 'Recover Account' }));

      await waitFor(() => {
        expect(mockRecoverWithFileAndServer).toHaveBeenCalledWith(
          mockRecoveryFileContents
        );
      });
    });

    it('should show success state after server recovery', async () => {
      mockOpen.mockResolvedValue('/path/to/recovery.recovery');
      mockReadTextFile.mockResolvedValue(mockRecoveryFileContents);

      const { user } = render(<RecoveryPage />);

      await user.click(
        screen.getByText('I have 1 recovery file + server share')
      );

      const uploadSlot = screen.getByText('Click to select .recovery file');
      await user.click(uploadSlot);

      await waitFor(() => {
        expect(screen.getByText('recovery.recovery')).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: 'Recover Account' }));

      await waitFor(() => {
        expect(screen.getByText('Account Recovered')).toBeInTheDocument();
      });
    });

    it('should show error when server recovery fails', async () => {
      mockRecoverWithFileAndServer.mockRejectedValue(
        new Error('Invalid share')
      );

      mockOpen.mockResolvedValue('/path/to/recovery.recovery');
      mockReadTextFile.mockResolvedValue(mockRecoveryFileContents);

      const { user } = render(<RecoveryPage />);

      await user.click(
        screen.getByText('I have 1 recovery file + server share')
      );

      const uploadSlot = screen.getByText('Click to select .recovery file');
      await user.click(uploadSlot);

      await waitFor(() => {
        expect(screen.getByText('recovery.recovery')).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: 'Recover Account' }));

      await waitFor(() => {
        expect(
          screen.getByText(/Recovery failed: Invalid share/)
        ).toBeInTheDocument();
      });
    });
  });

  describe('error dismissal', () => {
    it('should dismiss error when Dismiss is clicked', async () => {
      mockOpen.mockResolvedValue('/path/to/recovery1.recovery');
      mockReadTextFile.mockRejectedValue(new Error('Read error'));

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      const firstSlot = screen.getByText('First recovery file')
        .closest('div')!
        .querySelector('button')!;
      await user.click(firstSlot);

      await waitFor(() => {
        expect(
          screen.getByText(/Failed to read recovery file/)
        ).toBeInTheDocument();
      });

      await user.click(screen.getByText('Dismiss'));

      expect(
        screen.queryByText(/Failed to read recovery file/)
      ).not.toBeInTheDocument();
    });
  });

  describe('dialog cancellation', () => {
    it('should not pick file when dialog is cancelled', async () => {
      mockOpen.mockResolvedValue(null); // dialog cancelled

      const { user } = render(<RecoveryPage />);

      await user.click(screen.getByText('I have 2 recovery files'));

      const uploadSlots = screen.getAllByText('Click to select .recovery file');
      await user.click(uploadSlots[0]);

      // Should still show the empty slot text
      await waitFor(() => {
        expect(mockReadTextFile).not.toHaveBeenCalled();
      });
    });
  });
});
