import { X } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

type FileTypeFilter = 'all' | 'file' | 'folder';
type SharedStatusFilter = 'all' | 'shared' | 'not_shared' | 'received';

interface FileFiltersProps {
  typeFilter: FileTypeFilter;
  sharedStatusFilter: SharedStatusFilter;
  onTypeFilterChange: (value: FileTypeFilter) => void;
  onSharedStatusFilterChange: (value: SharedStatusFilter) => void;
  onClearFilters: () => void;
  hasActiveFilters: boolean;
}

export function FileFilters({
  typeFilter,
  sharedStatusFilter,
  onTypeFilterChange,
  onSharedStatusFilterChange,
  onClearFilters,
  hasActiveFilters,
}: FileFiltersProps) {
  return (
    <div className="flex items-center gap-3">
      <Select value={typeFilter} onValueChange={onTypeFilterChange}>
        <SelectTrigger className="w-32">
          <SelectValue placeholder="Type" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All Types</SelectItem>
          <SelectItem value="file">Files</SelectItem>
          <SelectItem value="folder">Folders</SelectItem>
        </SelectContent>
      </Select>

      <Select value={sharedStatusFilter} onValueChange={onSharedStatusFilterChange}>
        <SelectTrigger className="w-40">
          <SelectValue placeholder="Shared Status" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All</SelectItem>
          <SelectItem value="shared">Shared by me</SelectItem>
          <SelectItem value="received">Shared with me</SelectItem>
          <SelectItem value="not_shared">Not shared</SelectItem>
        </SelectContent>
      </Select>

      {hasActiveFilters && (
        <Button
          variant="ghost"
          size="sm"
          onClick={onClearFilters}
          className="text-muted-foreground hover:text-foreground"
        >
          <X className="h-4 w-4 mr-1" />
          Clear filters
        </Button>
      )}
    </div>
  );
}
