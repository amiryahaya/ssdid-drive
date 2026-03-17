import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import StatsCard from '../StatsCard'

describe('StatsCard', () => {
  it('renders title and numeric value', () => {
    render(<StatsCard title="Users" value={42} />)
    expect(screen.getByText('Users')).toBeInTheDocument()
    expect(screen.getByText('42')).toBeInTheDocument()
  })

  it('renders title and string value', () => {
    render(<StatsCard title="Storage" value="1.5 GB" />)
    expect(screen.getByText('Storage')).toBeInTheDocument()
    expect(screen.getByText('1.5 GB')).toBeInTheDocument()
  })

  it('renders with default gray accent', () => {
    const { container } = render(<StatsCard title="Test" value={0} />)
    expect(container.firstChild).toHaveClass('border-l-gray-300')
  })

  it('renders with blue accent', () => {
    const { container } = render(<StatsCard title="Test" value={0} accent="blue" />)
    expect(container.firstChild).toHaveClass('border-l-blue-500')
  })

  it('renders with green accent', () => {
    const { container } = render(<StatsCard title="Test" value={0} accent="green" />)
    expect(container.firstChild).toHaveClass('border-l-green-500')
  })

  it('renders with purple accent', () => {
    const { container } = render(<StatsCard title="Test" value={0} accent="purple" />)
    expect(container.firstChild).toHaveClass('border-l-purple-500')
  })

  it('renders with amber accent', () => {
    const { container } = render(<StatsCard title="Test" value={0} accent="amber" />)
    expect(container.firstChild).toHaveClass('border-l-amber-500')
  })

  it('renders icon when provided', () => {
    render(<StatsCard title="Test" value={0} icon={<span data-testid="test-icon">icon</span>} />)
    expect(screen.getByTestId('test-icon')).toBeInTheDocument()
  })

  it('does not render icon wrapper when no icon', () => {
    const { container } = render(<StatsCard title="Test" value={0} />)
    expect(container.querySelector('.text-gray-400')).toBeNull()
  })
})
