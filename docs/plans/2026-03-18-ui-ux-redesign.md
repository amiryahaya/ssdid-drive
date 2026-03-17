# UI/UX Redesign Plan — Mobile Clients

Based on Google Drive comparison analysis and CEO review (2026-03-18).

## Navigation Restructure — Option A (4 tabs)

```
  BEFORE (5 tabs — crowded):
  ┌────────────────────────────────────────────────────┐
  │  Files  │  Shares  │ Activity │ Notifs  │   More   │
  └────────────────────────────────────────────────────┘

  AFTER (4 tabs — clean):
  ┌──────────────────────────────────────────┐
  │  Home    │   Files   │  Shares  │  More  │
  │   🏠     │    📁     │   👥     │   •••  │
  └──────────────────────────────────────────┘
```

### Tab Contents

**Home** (NEW)
- Recent files (last 20, sorted by last accessed/modified)
- Starred/Favorite files section
- Quick actions row (Upload, Create Folder, Camera)
- Notification badge on Home icon when unread notifications exist

**Files** (existing, enhanced)
- Full file browser with folder navigation
- File type icons (PDF, image, video, doc, folder)
- Swipe actions (delete, share)
- Global search bar at top with type filter chips

**Shares** (existing, unchanged)
- Received shares / Created shares toggle
- Same functionality

**More** (consolidated)
- Notifications (with unread count)
- Activity log
- Settings (profile, security, devices, tenant switcher, invitations, members, recovery, credentials, linked logins)
- Logout

---

## Sprint UX-1: Navigation + Home Tab (1 week)

### 1. Home Tab — Recent Files
- `GET /api/files/recent?limit=20` endpoint (new)
- Show file type icon + name + last modified date
- Tap → file preview
- Empty state: "No recent files yet" with Upload button

### 2. Home Tab — Starred Files
- `GET /api/files?starred=true` endpoint (or filter param)
- Horizontal scroll card row or vertical list
- Tap → file preview
- Empty state: "Star important files for quick access"

### 3. Home Tab — Quick Actions Row
- 3 circular buttons: Upload File, Upload Photo, Create Folder
- Row sits below the search bar, above recent files
- Each triggers existing functionality (no new backend)

### 4. Bottom Navigation — 4 Tabs
- Replace 5-tab bar with 4: Home, Files, Shares, More
- Move Activity + Notifications into More menu
- Badge on More tab when unread notifications > 0
- Remember last-opened tab across app launches

### 5. More Screen
- Notifications row with unread count badge
- Activity row
- Divider
- Settings sections (existing)
- Logout at bottom

---

## Sprint UX-2: File Browser Enhancements (1 week)

### 6. File Type Icons
- Replace generic file icon with type-specific icons
- Types: PDF, Image (JPEG/PNG), Video, Audio, Text/Code, Spreadsheet, Presentation, Archive (ZIP), Folder, Unknown
- Use SF Symbols (iOS) / Material Icons (Android)
- Show thumbnail for images (already exists in grid view — extend to list view)

### 7. Global Search Bar
- Persistent search bar at top of Files tab (and Home tab)
- Search across ALL files in all folders (not just current folder)
- `GET /api/files/search?q=term&type=pdf&from=2026-01-01` (new endpoint)
- Filter chips below search bar: All, Documents, Images, Videos, PDFs
- Recent searches (stored locally, last 5)
- Empty state: "No files match your search"

### 8. Swipe Actions (iOS) / Long-Press Menu (Android)
- **iOS**: Swipe left → Delete (red), Swipe right → Share (blue)
- **Android**: Long-press → context menu: Share, Rename, Move, Delete, Star/Unstar
- Both: tap-and-hold for multi-select mode

### 9. Pull-to-Refresh
- Already exists but enhance with:
  - Haptic feedback on pull threshold
  - Smooth spring animation
  - Sync status text ("Last synced: 2 min ago")

---

## Sprint UX-3: Share Flow + Empty States (1 week)

### 10. Share Bottom Sheet
- Replace full-screen share dialog with bottom sheet (half-screen)
- Sections:
  1. Recipient search (autocomplete by name/email within org)
  2. Permission selector: segmented control (Read | Write)
  3. Optional expiry date picker
  4. "Share" primary button
- Show recipient avatar/initials circle
- Confirmation: snackbar "Shared with Alice" (not a dialog)

### 11. Empty State Illustrations
- Design custom illustrations for:
  - No files (Home + Files tab)
  - No shares (Shares tab)
  - No notifications (More → Notifications)
  - No activity (More → Activity)
  - No search results
- Each includes a primary action button
- Simple line art style, brand colors

### 12. Sharing Indicator on Files
- Small people icon (👥) overlay on file rows that are shared
- Visible in both grid and list views
- Tap indicator → jump to share details

---

## Sprint UX-4: Polish + Micro-interactions (1 week)

### 13. Expanded FAB (Speed Dial)
- Replace single (+) button with speed dial:
  - Tap → fan out: Upload File, Upload Photo, Create Folder
  - Background dim overlay when expanded
  - Spring animation on expand/collapse
- iOS: UIKit spring animation
- Android: Compose `AnimatedVisibility` with spring

### 14. Skeleton Loading
- Replace spinners with skeleton screens:
  - File list: 5 rows of gray shimmer placeholders
  - Share list: same pattern
  - Home tab: skeleton for recent + starred sections
- Use shimmer animation (left-to-right gradient sweep)

### 15. Haptic Feedback
- Add haptic on:
  - Star/unstar toggle (light impact)
  - Pull-to-refresh threshold (medium impact)
  - FAB expand (light impact)
  - Swipe action trigger (medium impact)
  - Successful share creation (success notification)
- iOS: UIImpactFeedbackGenerator
- Android: HapticFeedbackConstants

### 16. Dark Mode Audit
- Verify all screens render correctly in dark mode
- Check: text contrast, icon tint, card backgrounds, separator colors
- Fix any hardcoded colors (use semantic colors only)
- Test on both platforms

### 17. Merge Activity + Notifications
- In the More screen, consider a unified "Activity & Notifications" view
- Single chronological feed with type badges:
  - 🔔 Notification (share received, invite)
  - 📋 Activity (file uploaded, folder created, share revoked)
- Group by: Today, Yesterday, This Week, Earlier
- Inline action buttons: "View File", "Accept", "Dismiss"

---

## Feature Sprints (from roadmap, with UX considerations)

### Sprint F-1: Star/Favorite (S) — pairs with Sprint UX-1
- Add `is_starred` boolean to FileItem entity
- `PATCH /api/files/{id}/star` toggle endpoint
- Star icon on file rows (tap to toggle)
- Starred section on Home tab
- Animate star icon on toggle (scale + color)

### Sprint F-2: Trash / Soft Delete (M) — pairs with Sprint UX-2
- Soft delete with 30-day retention
- Trash view accessible from More menu
- "Undo" snackbar after delete (5 second window)
- Trash empty state: "Trash is empty"
- "Empty Trash" button with confirmation dialog

### Sprint F-3: Global Search (M) — pairs with Sprint UX-2
- `GET /api/files/search?q=term&type=pdf`
- Search bar + filter chips
- Highlight matching text in results
- Recent searches stored locally

### Sprint F-4: File Rename + Move (S)
- Rename: inline text edit on long-press
- Move: folder picker bottom sheet
- Both use existing PATCH endpoint

### Sprint F-5: Storage Quota Display (S)
- Progress bar in Settings: "2.3 GB / 10 GB used"
- Color changes: green (<70%), yellow (70-90%), red (>90%)
- Tap for breakdown (files, shares, trash)

### Sprint F-6: Offline File Access (L)
- "Make available offline" toggle per file
- Download + decrypt to local encrypted cache
- Cloud icon with checkmark for offline-available files
- Sync on reconnect
- Storage management in Settings

### Sprint F-7: Version History (L)
- "Version history" in file context menu
- List of versions with timestamp + size
- "Restore this version" button
- Retention configurable per tenant

---

## Platform-Specific Notes

### iOS
- Use UIKit (existing architecture) — don't migrate to SwiftUI
- SF Symbols for all icons (consistent with system)
- UIContextMenuInteraction for long-press context menus
- UISwipeActionsConfiguration for swipe actions
- Sheet presentation for bottom sheets (iOS 15+)

### Android
- Material 3 dynamic color (already using Compose Material3)
- Material Icons for file type icons
- ModalBottomSheet for share flow
- DropdownMenu for context menus
- SwipeToDismiss for swipe actions
- Use Compose animation APIs (animateFloatAsState, AnimatedVisibility)

---

## Design Tokens (shared across platforms)

```
Spacing:
  xs: 4dp/pt
  sm: 8dp/pt
  md: 16dp/pt
  lg: 24dp/pt
  xl: 32dp/pt

Corner radius:
  card: 12dp/pt
  button: 8dp/pt
  chip: 16dp/pt (full round)
  dialog: 16dp/pt

Typography:
  title: 24sp/pt semibold
  subtitle: 18sp/pt medium
  body: 16sp/pt regular
  caption: 13sp/pt regular
  mono: 13sp/pt monospace (for DID, file sizes)

Colors (semantic):
  primary: brand blue
  surface: system background
  onSurface: system label
  error: system red
  success: system green
  warning: system yellow
  badge: brand blue (notifications)
```

---

## Implementation Order

```
  Week 1: Sprint UX-1 (Navigation + Home Tab)
           + Sprint F-1 (Star/Favorite)

  Week 2: Sprint UX-2 (File Browser)
           + Sprint F-3 (Global Search)
           + Sprint F-4 (Rename + Move)

  Week 3: Sprint UX-3 (Share Flow + Empty States)
           + Sprint F-2 (Trash)
           + Sprint F-5 (Storage Quota)

  Week 4: Sprint UX-4 (Polish)
           + Sprint F-6 (Offline — start)

  Week 5-6: Sprint F-6 (Offline — complete)
             + Sprint F-7 (Version History)
```

## Explicitly Deferred

| Item | Reason |
|------|--------|
| SwiftUI migration | Too risky mid-development — stay UIKit |
| Custom font | System fonts are fine for enterprise |
| Animated onboarding | Current carousel is sufficient |
| Tablet-specific layout | iPad Catalyst already works |
| Widget (iOS/Android) | Low priority for enterprise |
| Apple Watch app | Out of scope |
