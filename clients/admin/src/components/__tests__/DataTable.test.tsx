import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import DataTable from '../DataTable'
import type { Column } from '../DataTable'

interface TestItem {
  id: string
  name: string
  value: number
}

const columns: Column<TestItem>[] = [
  { key: 'name', header: 'Name' },
  { key: 'value', header: 'Value' },
]

const sampleData: TestItem[] = [
  { id: '1', name: 'Alpha', value: 10 },
  { id: '2', name: 'Beta', value: 20 },
]

describe('DataTable', () => {
  it('renders column headers', () => {
    render(<DataTable columns={columns} data={[]} />)
    expect(screen.getByText('Name')).toBeInTheDocument()
    expect(screen.getByText('Value')).toBeInTheDocument()
  })

  it('renders data rows using default string rendering', () => {
    render(<DataTable columns={columns} data={sampleData} rowKey={(item) => item.id} />)
    expect(screen.getByText('Alpha')).toBeInTheDocument()
    expect(screen.getByText('10')).toBeInTheDocument()
    expect(screen.getByText('Beta')).toBeInTheDocument()
    expect(screen.getByText('20')).toBeInTheDocument()
  })

  it('uses custom render function when provided', () => {
    const customColumns: Column<TestItem>[] = [
      { key: 'name', header: 'Name', render: (item) => <strong>{item.name.toUpperCase()}</strong> },
      { key: 'value', header: 'Value' },
    ]
    render(<DataTable columns={customColumns} data={sampleData} rowKey={(item) => item.id} />)
    expect(screen.getByText('ALPHA')).toBeInTheDocument()
  })

  it('shows skeleton rows when loading', () => {
    const { container } = render(<DataTable columns={columns} data={[]} loading={true} skeletonRows={3} />)
    const pulseRows = container.querySelectorAll('tr.animate-pulse')
    expect(pulseRows.length).toBe(3)
  })

  it('uses default 5 skeleton rows when skeletonRows not specified', () => {
    const { container } = render(<DataTable columns={columns} data={[]} loading={true} />)
    const pulseRows = container.querySelectorAll('tr.animate-pulse')
    expect(pulseRows.length).toBe(5)
  })

  it('shows "No data found" when not loading and data is empty', () => {
    render(<DataTable columns={columns} data={[]} />)
    expect(screen.getByText('No data found')).toBeInTheDocument()
  })

  it('does not show "No data found" when loading', () => {
    render(<DataTable columns={columns} data={[]} loading={true} />)
    expect(screen.queryByText('No data found')).not.toBeInTheDocument()
  })

  it('does not show "No data found" when data is present', () => {
    render(<DataTable columns={columns} data={sampleData} rowKey={(item) => item.id} />)
    expect(screen.queryByText('No data found')).not.toBeInTheDocument()
  })
})
