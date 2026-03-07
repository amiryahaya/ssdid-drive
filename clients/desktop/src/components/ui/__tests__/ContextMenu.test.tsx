import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import {
  ContextMenu,
  ContextMenuTrigger,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuCheckboxItem,
  ContextMenuRadioItem,
  ContextMenuLabel,
  ContextMenuSeparator,
  ContextMenuShortcut,
  ContextMenuGroup,
  ContextMenuSub,
  ContextMenuSubContent,
  ContextMenuSubTrigger,
  ContextMenuRadioGroup,
} from '../ContextMenu';

describe('ContextMenu', () => {
  it('should render trigger element', () => {
    render(
      <ContextMenu>
        <ContextMenuTrigger>Right click me</ContextMenuTrigger>
        <ContextMenuContent>
          <ContextMenuItem>Item 1</ContextMenuItem>
        </ContextMenuContent>
      </ContextMenu>
    );

    expect(screen.getByText('Right click me')).toBeInTheDocument();
  });

  it('should show menu on right click', async () => {
    render(
      <ContextMenu>
        <ContextMenuTrigger>Right click me</ContextMenuTrigger>
        <ContextMenuContent>
          <ContextMenuItem>Menu Item</ContextMenuItem>
        </ContextMenuContent>
      </ContextMenu>
    );

    const trigger = screen.getByText('Right click me');
    fireEvent.contextMenu(trigger);

    await waitFor(() => {
      expect(screen.getByText('Menu Item')).toBeInTheDocument();
    });
  });

  it('should render ContextMenuItem with inset prop', async () => {
    render(
      <ContextMenu>
        <ContextMenuTrigger>Trigger</ContextMenuTrigger>
        <ContextMenuContent>
          <ContextMenuItem inset>Inset Item</ContextMenuItem>
        </ContextMenuContent>
      </ContextMenu>
    );

    fireEvent.contextMenu(screen.getByText('Trigger'));

    await waitFor(() => {
      const item = screen.getByText('Inset Item');
      expect(item).toBeInTheDocument();
      expect(item).toHaveClass('pl-8');
    });
  });

  describe('ContextMenuLabel', () => {
    it('should render label text', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuLabel>My Label</ContextMenuLabel>
            <ContextMenuItem>Item</ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        expect(screen.getByText('My Label')).toBeInTheDocument();
      });
    });

    it('should apply inset styling when inset prop is true', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuLabel inset>Inset Label</ContextMenuLabel>
            <ContextMenuItem>Item</ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        const label = screen.getByText('Inset Label');
        expect(label).toHaveClass('pl-8');
      });
    });
  });

  describe('ContextMenuSeparator', () => {
    it('should render separator element', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuItem>Item 1</ContextMenuItem>
            <ContextMenuSeparator data-testid="separator" />
            <ContextMenuItem>Item 2</ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        expect(screen.getByText('Item 1')).toBeInTheDocument();
        expect(screen.getByText('Item 2')).toBeInTheDocument();
        expect(screen.getByTestId('separator')).toBeInTheDocument();
      });
    });
  });

  describe('ContextMenuShortcut', () => {
    it('should render shortcut text', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuItem>
              Cut <ContextMenuShortcut>Ctrl+X</ContextMenuShortcut>
            </ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        expect(screen.getByText('Ctrl+X')).toBeInTheDocument();
      });
    });

    it('should apply custom className', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuItem>
              Copy <ContextMenuShortcut className="custom-shortcut">Ctrl+C</ContextMenuShortcut>
            </ContextMenuItem>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        const shortcut = screen.getByText('Ctrl+C');
        expect(shortcut).toHaveClass('custom-shortcut');
      });
    });
  });

  describe('ContextMenuCheckboxItem', () => {
    it('should render checkbox item', async () => {
      const onCheckedChange = vi.fn();
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuCheckboxItem checked={false} onCheckedChange={onCheckedChange}>
              Checkbox Item
            </ContextMenuCheckboxItem>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        expect(screen.getByText('Checkbox Item')).toBeInTheDocument();
      });
    });
  });

  describe('ContextMenuRadioItem', () => {
    it('should render radio items in a group', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuRadioGroup value="option1">
              <ContextMenuRadioItem value="option1">Option 1</ContextMenuRadioItem>
              <ContextMenuRadioItem value="option2">Option 2</ContextMenuRadioItem>
            </ContextMenuRadioGroup>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        expect(screen.getByText('Option 1')).toBeInTheDocument();
        expect(screen.getByText('Option 2')).toBeInTheDocument();
      });
    });
  });

  describe('ContextMenuSubTrigger', () => {
    it('should render sub trigger', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuSub>
              <ContextMenuSubTrigger>More Options</ContextMenuSubTrigger>
              <ContextMenuSubContent>
                <ContextMenuItem>Sub Item</ContextMenuItem>
              </ContextMenuSubContent>
            </ContextMenuSub>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        expect(screen.getByText('More Options')).toBeInTheDocument();
      });
    });

    it('should apply inset styling', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuSub>
              <ContextMenuSubTrigger inset>Inset Sub Trigger</ContextMenuSubTrigger>
              <ContextMenuSubContent>
                <ContextMenuItem>Sub Item</ContextMenuItem>
              </ContextMenuSubContent>
            </ContextMenuSub>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        const subTrigger = screen.getByText('Inset Sub Trigger');
        expect(subTrigger).toHaveClass('pl-8');
      });
    });
  });

  describe('ContextMenuGroup', () => {
    it('should render grouped items', async () => {
      render(
        <ContextMenu>
          <ContextMenuTrigger>Trigger</ContextMenuTrigger>
          <ContextMenuContent>
            <ContextMenuGroup>
              <ContextMenuItem>Group Item 1</ContextMenuItem>
              <ContextMenuItem>Group Item 2</ContextMenuItem>
            </ContextMenuGroup>
          </ContextMenuContent>
        </ContextMenu>
      );

      fireEvent.contextMenu(screen.getByText('Trigger'));

      await waitFor(() => {
        expect(screen.getByText('Group Item 1')).toBeInTheDocument();
        expect(screen.getByText('Group Item 2')).toBeInTheDocument();
      });
    });
  });
});
