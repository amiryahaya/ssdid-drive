interface PaginationProps {
  page: number
  totalPages: number
  loading: boolean
  total: number
  onChange: (page: number) => void
}

export default function Pagination({ page, totalPages, loading, total, onChange }: PaginationProps) {
  if (loading || total === 0) return null

  return (
    <div className="flex items-center justify-between mt-4 text-sm text-gray-600">
      <span>
        Page {page} of {totalPages}
      </span>
      <div className="flex gap-2">
        <button
          onClick={() => onChange(Math.max(1, page - 1))}
          disabled={page <= 1}
          className="px-3 py-1 border border-gray-300 rounded hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Previous
        </button>
        <button
          onClick={() => onChange(Math.min(totalPages, page + 1))}
          disabled={page >= totalPages}
          className="px-3 py-1 border border-gray-300 rounded hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Next
        </button>
      </div>
    </div>
  )
}
