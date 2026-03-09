# Admin SPA UI/UX Redesign

## Goal

Redesign the admin dashboard with a collapsible sidebar layout, refined visual styling (Linear/Vercel-inspired clean minimal), and responsive behavior for mobile/tablet.

## Architecture

Replace the current top-nav horizontal layout with a sidebar + header layout. The sidebar is the primary navigation element, collapsible to icon-only mode. On mobile, it becomes an overlay drawer. No new dependencies — pure Tailwind CSS with inline SVG icons.

## Layout Structure

```
┌────────────────────────────────────────────────┐
│ Sidebar (240px)  │  Header (page title + user) │
│                  │─────────────────────────────│
│  Logo/Brand      │                             │
│  ─────────       │  Page Content               │
│  Dashboard       │                             │
│  Users           │                             │
│  Tenants         │                             │
│  Audit Log       │                             │
│                  │                             │
│  ─────────       │                             │
│  Collapse toggle │                             │
│  User info       │                             │
└────────────────────────────────────────────────┘
```

**Collapsed state (64px):** Icons only, tooltip on hover for labels.

## Responsive Behavior

| Breakpoint | Sidebar | Trigger |
|------------|---------|---------|
| Desktop (>=1024px) | Full (240px), collapsible | Toggle button |
| Tablet (768-1023px) | Collapsed (64px) by default | Toggle button |
| Mobile (<768px) | Hidden, overlay drawer | Hamburger in header |

## Visual Style

- **Palette:** White backgrounds, gray-50 content area, gray-200 borders. Blue-600 for active states and primary actions.
- **Sidebar:** White background, left border accent (blue-600, 3px) on active nav item. Subtle hover (gray-50).
- **Header:** White, bottom border, contains page title on left, user name + sign out on right.
- **Cards (StatsCard):** White, rounded-xl, subtle shadow-sm, left-border color accent per metric type.
- **Tables:** Same DataTable but with refined padding, rounded container.
- **Dialogs:** Backdrop blur, centered modal, rounded-xl.
- **Typography:** System font stack (already via Tailwind). Tighter line-height on headings.

## Components

### New
- `Sidebar.tsx` — collapsible nav with icons, active state, collapse toggle, user info
- `Layout.tsx` — sidebar + header + content wrapper, manages sidebar state and mobile drawer

### Modified
- `App.tsx` — replace inline header/nav with Layout component
- `StatsCard.tsx` — add accent color prop, refined spacing
- `DataTable.tsx` — minor padding/styling refinements
- `LoginPage.tsx` — updated branding area styling
- Dialog components — consistent backdrop blur styling

### Icons (inline SVG)
- Dashboard: grid/squares icon
- Users: people icon
- Tenants: building icon
- Audit Log: clipboard/list icon
- Collapse: chevron-left/right
- Menu: hamburger (mobile)

## What Does NOT Change
- Same 6 pages, same functionality
- Same API integration and stores
- Same Zustand state management
- No new npm dependencies
