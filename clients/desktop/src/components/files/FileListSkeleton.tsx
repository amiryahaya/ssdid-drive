import { Skeleton, SkeletonText } from '@/components/ui/Skeleton';

interface FileListSkeletonProps {
  count?: number;
}

export function FileListSkeleton({ count = 5 }: FileListSkeletonProps) {
  return (
    <div
      className="border rounded-lg overflow-hidden"
      role="status"
      aria-label="Loading files"
    >
      <table className="w-full">
        <thead className="bg-muted/50">
          <tr className="text-left text-sm">
            <th className="px-4 py-3 w-10">
              <Skeleton className="h-5 w-5" />
            </th>
            <th className="px-4 py-3 font-medium">Name</th>
            <th className="px-4 py-3 font-medium">Size</th>
            <th className="px-4 py-3 font-medium">Modified</th>
            <th className="px-4 py-3 font-medium w-12"></th>
          </tr>
        </thead>
        <tbody className="divide-y">
          {Array.from({ length: count }).map((_, index) => (
            <tr key={index} className="animate-pulse">
              <td className="px-4 py-3">
                <Skeleton className="h-5 w-5" />
              </td>
              <td className="px-4 py-3">
                <div className="flex items-center gap-3">
                  <Skeleton className="h-5 w-5" />
                  <SkeletonText className="w-32" />
                </div>
              </td>
              <td className="px-4 py-3">
                <SkeletonText className="w-16" />
              </td>
              <td className="px-4 py-3">
                <SkeletonText className="w-24" />
              </td>
              <td className="px-4 py-3">
                <Skeleton className="h-8 w-8" />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <span className="sr-only">Loading file list...</span>
    </div>
  );
}

export function FileGridSkeleton({ count = 12 }: FileListSkeletonProps) {
  return (
    <div
      className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4"
      role="status"
      aria-label="Loading files"
    >
      {Array.from({ length: count }).map((_, index) => (
        <div
          key={index}
          className="p-4 rounded-lg border animate-pulse"
        >
          <div className="flex flex-col items-center pt-4">
            <Skeleton className="h-12 w-12 mb-3" />
            <SkeletonText className="w-20 mb-1" />
            <Skeleton className="h-3 w-12" />
          </div>
        </div>
      ))}
      <span className="sr-only">Loading file list...</span>
    </div>
  );
}
