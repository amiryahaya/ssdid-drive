import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import Pagination from '../Pagination'

describe('Pagination', () => {
  it('renders nothing when loading', () => {
    const { container } = render(
      <Pagination page={1} totalPages={5} loading={true} total={100} onChange={vi.fn()} />
    )
    expect(container.firstChild).toBeNull()
  })

  it('renders nothing when total is 0', () => {
    const { container } = render(
      <Pagination page={1} totalPages={0} loading={false} total={0} onChange={vi.fn()} />
    )
    expect(container.firstChild).toBeNull()
  })

  it('renders page info and navigation buttons', () => {
    render(
      <Pagination page={2} totalPages={5} loading={false} total={100} onChange={vi.fn()} />
    )
    expect(screen.getByText('Page 2 of 5')).toBeInTheDocument()
    expect(screen.getByText('Previous')).toBeInTheDocument()
    expect(screen.getByText('Next')).toBeInTheDocument()
  })

  it('disables Previous button on first page', () => {
    render(
      <Pagination page={1} totalPages={5} loading={false} total={100} onChange={vi.fn()} />
    )
    expect(screen.getByText('Previous')).toBeDisabled()
    expect(screen.getByText('Next')).not.toBeDisabled()
  })

  it('disables Next button on last page', () => {
    render(
      <Pagination page={5} totalPages={5} loading={false} total={100} onChange={vi.fn()} />
    )
    expect(screen.getByText('Next')).toBeDisabled()
    expect(screen.getByText('Previous')).not.toBeDisabled()
  })

  it('calls onChange with previous page when Previous is clicked', async () => {
    const user = userEvent.setup()
    const onChange = vi.fn()
    render(
      <Pagination page={3} totalPages={5} loading={false} total={100} onChange={onChange} />
    )
    await user.click(screen.getByText('Previous'))
    expect(onChange).toHaveBeenCalledWith(2)
  })

  it('calls onChange with next page when Next is clicked', async () => {
    const user = userEvent.setup()
    const onChange = vi.fn()
    render(
      <Pagination page={3} totalPages={5} loading={false} total={100} onChange={onChange} />
    )
    await user.click(screen.getByText('Next'))
    expect(onChange).toHaveBeenCalledWith(4)
  })

  it('does not go below page 1', () => {
    const onChange = vi.fn()
    render(
      <Pagination page={1} totalPages={5} loading={false} total={100} onChange={onChange} />
    )
    // Previous is disabled, but let's verify the logic
    expect(screen.getByText('Previous')).toBeDisabled()
  })

  it('does not go above totalPages', () => {
    const onChange = vi.fn()
    render(
      <Pagination page={5} totalPages={5} loading={false} total={100} onChange={onChange} />
    )
    expect(screen.getByText('Next')).toBeDisabled()
  })
})
