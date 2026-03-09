export function formatDate(iso: string | null): string {
  if (!iso) return '\u2014'
  return new Date(iso).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

export function formatDateTime(iso: string | null): string {
  if (!iso) return '\u2014'
  return new Date(iso).toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function formatStorageQuota(bytes: number | null): string {
  if (bytes === null || bytes === 0) return 'Unlimited'
  const gb = bytes / (1024 * 1024 * 1024)
  if (gb >= 1) return `${gb.toFixed(gb % 1 === 0 ? 0 : 1)} GB`
  const mb = bytes / (1024 * 1024)
  if (mb >= 1) return `${mb.toFixed(mb % 1 === 0 ? 0 : 1)} MB`
  return `${bytes} B`
}

export function truncateDid(did: string): string {
  if (did.length <= 24) return did
  return `${did.slice(0, 16)}...${did.slice(-8)}`
}
