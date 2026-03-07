# SecureSharing Feature Roadmap

This document outlines all planned features for SecureSharing across all platforms (Android, iOS, Desktop).

## Current Implementation Status

### Core Features (Implemented)

| Feature | Android | iOS | Desktop (Tauri) | Backend |
|---------|:-------:|:---:|:---------------:|:-------:|
| User registration with PQC key generation | ✅ | ✅ | ✅ | ✅ |
| Invitation-based registration | ✅ | ✅ | ✅ | ✅ |
| Login with key derivation | ✅ | ✅ | ✅ | ✅ |
| Multi-tenant support | ✅ | ✅ | ✅ | ✅ |
| Tenant switching | ✅ | ✅ | ✅ | ✅ |
| File browser with folders | ✅ | ✅ | ✅ | ✅ |
| File upload with encryption | ✅ | ✅ | ✅ | ✅ |
| File download with decryption | ✅ | ✅ | ✅ | ✅ |
| File preview (text, images, PDF, video) | ✅ | ✅ | ✅ | N/A |
| File rename/move/copy | ✅ | ✅ | ✅ | ✅ |
| File/folder sharing | ✅ | ✅ | ✅ | ✅ |
| Share permissions (view/edit/download) | ✅ | ✅ | ✅ | ✅ |
| Share expiration | ✅ | ✅ | ✅ | ✅ |
| Received/Created shares view | ✅ | ✅ | ✅ | ✅ |
| Share accept/decline/revoke | ✅ | ✅ | ✅ | ✅ |
| Shamir recovery system | ✅ | ✅ | ✅ | ✅ |
| Recovery setup (threshold config) | ✅ | ✅ | ✅ | ✅ |
| Trustee selection | ✅ | ✅ | ✅ | ✅ |
| Recovery initiation | ✅ | ✅ | ✅ | ✅ |
| Recovery approval (trustee) | ✅ | ✅ | ✅ | ✅ |
| Device enrollment | ✅ | ✅ | ✅ | ✅ |
| Device list/revocation | ✅ | ✅ | ✅ | ✅ |
| Biometric unlock | ✅ | ✅ | ✅ | N/A |
| Auto-lock timeout | ✅ | ✅ | ✅ | N/A |
| Screenshot prevention | ✅ | ✅ | N/A | N/A |
| Secure clipboard | ✅ | ✅ | ✅ | N/A |
| Push notifications (OneSignal) | ✅ | ✅ | ✅ | ✅ |
| Local database caching | ✅ | ✅ | ✅ | N/A |
| Offline mode with sync | ✅ | ✅ | ✅ | N/A |
| File search | ✅ | ✅ | ✅ | N/A |
| Multi-select / bulk operations | ✅ | ✅ | ✅ | ✅ |
| Favorites | ✅ | ✅ | ✅ | N/A |
| Sorting (name, date, size, type) | ✅ | ✅ | ✅ | N/A |
| View modes (list/grid) | ✅ | ✅ | ✅ | N/A |
| Share extension (receive from other apps) | ✅ | ✅ | N/A | N/A |
| Deep link handling | ✅ | ✅ | ✅ | N/A |
| Email notifications | N/A | N/A | N/A | ✅ |
| Notification read tracking | ✅ | ✅ | ✅ | ✅ |
| Notification filtering | ✅ | ✅ | ✅ | N/A |
| Cache management | ✅ | ✅ | ✅ | N/A |
| Crash reporting (Sentry) | ✅ | ✅ | ✅ | N/A |
| Password change | ✅ | ✅ | ✅ | ✅ |
| Edit profile | ✅ | ✅ | ✅ | ✅ |
| Settings screens | ✅ | ✅ | ✅ | N/A |
| Dark mode / theming | ✅ | ✅ | ✅ | N/A |
| Onboarding flow | ✅ | ✅ | ✅ | N/A |
| File Provider extension (Finder/Files) | N/A | ✅ | ✅ | N/A |
| Menu Bar app | N/A | N/A | ✅ | N/A |
| Drag and Drop | N/A | N/A | ✅ | N/A |
| Keyboard shortcuts | N/A | N/A | ✅ | N/A |

**Legend:** ✅ Implemented | 📋 Planned | ⬜ Not Started | N/A Not Applicable

---

## Planned Features

### 1. Security Enhancements

#### 1.1 Watermarking
**Priority: Low**

Add watermarks to document previews to deter unauthorized sharing of screenshots.

**Watermark Types:**
- **Visible**: User email/name overlaid on document
- **Invisible**: Steganographic watermark embedded in rendered preview

**Watermark Content:**
- User email
- Timestamp
- Device ID
- Custom text (tenant-configurable)

| Platform | Implementation |
|----------|----------------|
| Android | Canvas overlay on preview composables |
| iOS | Core Graphics overlay |
| Desktop | Canvas overlay in React component |

---

#### 1.2 Access Logging (Audit Trail)
**Priority: Medium**

Show users when and where their files were accessed.

**Logged Events:**
- File viewed
- File downloaded
- File shared
- Share accessed by recipient
- File modified

**Display:**
- Last accessed timestamp on file list
- Detailed access history in file details
- Export audit log

**Backend Changes:**
- Already have `audit_events` table
- Add API endpoint: `GET /api/files/{id}/access-log`

---

### 2. File Features

#### 2.1 File Versioning
**Priority: Low**

View and restore previous versions of files.

**Features:**
- List previous versions with timestamps
- Preview old versions
- Restore to previous version
- Delete old versions to save space
- Configurable retention (e.g., keep last 10 versions)

**Backend Changes:**
- `file_versions` table
- Version on each upload (not just metadata update)
- Storage consideration: each version is a separate encrypted blob

---

#### 2.2 File Tags/Labels
**Priority: Low**

Organize files with custom tags.

**Features:**
- Create custom tags with colors
- Apply multiple tags per file
- Filter files by tag
- Tag management (rename, delete, merge)

**Storage:**
- Tags encrypted in file metadata
- Or separate encrypted tags field

---

### 3. Sharing Enhancements

#### 3.1 Share Links
**Priority: Medium**

Generate time-limited shareable links for external users.

**Features:**
- Generate unique link for file/folder
- Set expiration (1 hour, 1 day, 7 days, 30 days, custom)
- Set access limit (number of downloads)
- Optional password protection
- Revoke link anytime

**Security Considerations:**
- Link contains encrypted key material
- Server cannot decrypt without link token
- One-time key derivation per access

**Backend Changes:**
- `share_links` table with token, expiry, access_count
- Public endpoint for link access

---

#### 3.2 Share Expiry Notifications
**Priority: Low**

Notify users when shared access is about to expire.

**Notifications:**
- 24 hours before expiry
- On expiry
- Option to extend from notification

---

#### 3.3 View-Only Mode
**Priority: Medium**

Allow recipients to view but not download files.

**Implementation:**
- Stream decrypted content without providing full file
- Disable download button
- Enhanced screenshot prevention
- Watermark with viewer info

**Limitations:**
- Cannot prevent all forms of capture
- Best effort protection

---

#### 3.4 Share Analytics
**Priority: Low**

Track who viewed shared files and when.

**Metrics:**
- View count per recipient
- Last viewed timestamp
- Download count (if allowed)
- Access location (country/region)

---

#### 3.5 Group Sharing
**Priority: Medium**

Share with predefined groups of users.

**Features:**
- Create groups within tenant
- Add/remove group members
- Share to group (all members get access)
- Group permissions (viewer, editor)

**Backend Changes:**
- `groups` table
- `group_members` table
- `share_grants` supports group_id

---

### 4. Collaboration

#### 4.1 Comments
**Priority: Low**

Add encrypted comments to files.

**Features:**
- Add comments to files
- Reply to comments (threaded)
- Edit/delete own comments
- Notifications for new comments

**Security:**
- Comments encrypted with file's DEK
- Only users with file access can read comments

**Backend Changes:**
- `file_comments` table with encrypted content

---

#### 4.2 Activity Feed
**Priority: Medium**

See recent activity on shared files.

**Activity Types:**
- Files shared with you
- Files you shared accessed
- Comments on your files
- Recovery requests

**UI:**
- Activity tab/screen
- Grouped by date
- Mark as read

---

### 5. UX Improvements

#### 5.1 Home Screen Widget
**Priority: Low**

Quick actions from home screen.

| Platform | Widget Features |
|----------|-----------------|
| Android | Quick upload, recent files, storage usage |
| iOS | Quick upload, recent files (WidgetKit) |

---

#### 5.2 Quick Preview
**Priority: Low**

Swipe through files without opening each one.

**Features:**
- Swipe left/right to navigate files
- Pinch to zoom
- Quick actions (share, download, delete)

---

### 6. iOS-Specific Pending

#### 6.1 Deep Link Handling
**Priority: Medium**

Handle invitation and share deep links.

**Status:** ✅ Implemented in Android and iOS.

---

#### 6.2 Notification Read Tracking
**Priority: Medium**

Mark notifications as read and track read status.

**Status:** ✅ Implemented in Android and iOS.

---

## Implementation Priority

### Phase 1: Security & Core UX (Completed)
1. ~~Biometric unlock~~ ✅ Completed (Android + iOS)
2. ~~Auto-lock timeout~~ ✅ Completed (Android + iOS)
3. ~~Push notifications~~ ✅ Completed (Android + iOS)
4. ~~Offline mode with sync~~ ✅ Completed (Android + iOS)
5. ~~File search~~ ✅ Completed (Android + iOS)
6. ~~Share extension~~ ✅ Completed (Android + iOS)

### Phase 1.5: iOS Feature Parity ✅ Complete
7. ~~Tenant switching (iOS)~~ ✅ Completed
8. ~~Deep link handling (iOS)~~ ✅ Completed
9. ~~Notification read tracking (iOS)~~ ✅ Completed
10. ~~Crash reporting - Sentry (iOS)~~ ✅ Completed

### Phase 2: Desktop App (Tauri/Rust) ✅ Complete
11. ~~Foundation - Tauri setup, KAZ native builds~~ ✅ Completed
12. ~~Core backend - 74 commands across 10 modules~~ ✅ Completed
13. ~~Frontend - React + TypeScript UI~~ ✅ Completed
14. ~~CI/CD - GitHub Actions for macOS/Windows builds~~ ✅ Completed
15. ~~Account management - Password change, profile edit, device management~~ ✅ Completed
16. ~~Onboarding flow - Multi-step welcome experience~~ ✅ Completed
17. ~~Multi-tenant support - Organization switching with role indicators~~ ✅ Completed
18. ~~Biometric unlock - Windows Hello/Touch ID with runtime availability detection~~ ✅ Completed
19. ~~Keyboard shortcuts - Navigation, file operations, selection, view modes~~ ✅ Completed
20. ~~Menu Bar app - System tray with quick actions, recent files, sync status~~ ✅ Completed
21. ~~Offline mode with sync - Queue operations offline, sync when online~~ ✅ Completed

### Phase 3: Sharing & Collaboration
16. Share links
17. Group sharing
18. Activity feed
19. View-only mode

### Phase 4: Polish
20. Watermarking
21. File versioning
22. Comments
23. Tags/labels
24. Widgets

---

## Platform-Specific Notes

### Android
- Min SDK: 24 (Android 7.0)
- Target SDK: 34
- Architecture: MVVM + Clean Architecture
- UI: Jetpack Compose + Material3
- DI: Hilt
- Crypto: KAZ-KEM, KAZ-SIGN (JNI), ML-KEM, ML-DSA (liboqs)

### iOS
- Min iOS: 15.0
- Architecture: MVVM + Clean Architecture
- UI: UIKit + Coordinators
- Crypto: KAZ-KEM, KAZ-SIGN (XCFramework), ML-KEM, ML-DSA (placeholder)
- Extensions: Share Extension, File Provider Extension

### Desktop (Tauri/Rust) - macOS & Windows
- Min macOS: 11.0 (Big Sur)
- Min Windows: 10 (1903+)
- Framework: Tauri 2.x + Rust backend
- Frontend: React 18 + TypeScript + Vite
- UI: Radix UI + Tailwind CSS
- Architecture: Commands → Services → API Client
- Crypto: KAZ-KEM, KAZ-SIGN (native FFI), ML-KEM-768, ML-DSA-65 (securesharing-crypto)
- Storage: SQLite (rusqlite) + OS Keychain (keyring-rs)
- Security: Argon2id key derivation, Zeroize on sensitive data, path traversal prevention
- Build: GitHub Actions CI/CD for x86_64 and ARM64 (DMG, MSI, NSIS)
- Test Coverage: ~90% frontend, comprehensive backend
- Status: **100% production-ready** - All planned features implemented

---

## Backend API Requirements

### Implemented Endpoints

| Feature | Endpoint | Method | Status |
|---------|----------|--------|--------|
| Push tokens | `/api/devices/{id}/push` | POST, DELETE | ✅ Implemented |
| Notifications | `/api/notifications` | GET | ✅ Implemented |
| Notification count | `/api/notifications/unread_count` | GET | ✅ Implemented |
| Mark read | `/api/notifications/{id}/read` | POST | ✅ Implemented |
| Mark all read | `/api/notifications/read_all` | POST | ✅ Implemented |
| Dismiss | `/api/notifications/{id}` | DELETE | ✅ Implemented |
| Recovery shares (owner) | `/api/recovery/shares/created` | GET | ✅ Implemented |
| Invitations | `/api/invitations` | GET, POST | ✅ Implemented |
| Accept invitation | `/api/invitations/{token}/accept` | POST | ✅ Implemented |

### Planned Endpoints

| Feature | Endpoint | Method |
|---------|----------|--------|
| Access logging | `/api/files/{id}/access-log` | GET |
| Favorites (server-side) | `/api/favorites` | GET, POST, DELETE |
| File versions | `/api/files/{id}/versions` | GET |
| File versions | `/api/files/{id}/versions/{version_id}/restore` | POST |
| Share links | `/api/share-links` | POST |
| Share links | `/api/share-links/{token}` | GET, DELETE |
| Share links (public) | `/api/public/share/{token}` | GET |
| Groups | `/api/groups` | GET, POST |
| Groups | `/api/groups/{id}` | GET, PUT, DELETE |
| Group members | `/api/groups/{id}/members` | GET, POST, DELETE |
| Comments | `/api/files/{id}/comments` | GET, POST |
| Comments | `/api/comments/{id}` | PUT, DELETE |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.13 | 2026-01-22 | Added macOS File Provider extension (Finder integration): Swift extension with NSFileProviderReplicatedExtension, FileProviderItem, FileProviderEnumerator; shared helpers (KeychainHelper, SharedDefaults, APIClient); Rust AppGroupService for IPC; 7 new Tauri commands; useFileProvider hook; Xcode project with build scripts; CI/CD integration |
| 2.12 | 2026-01-22 | **Desktop 100% Complete**: Added Offline mode with sync (SyncService, offline queue, file caching, useSync hook), moved CI/CD workflows to root .github folder with path filters for monorepo; updated command count to 67 across 9 modules |
| 2.11 | 2026-01-22 | Added Menu Bar app for Desktop: System tray with dynamic menu (Open, Quick Upload, Recent Files submenu, Notifications with badge, Sync Status indicator, Settings, Quit), tray event handlers, useTray hook for frontend sync, keyboard accelerators |
| 2.10 | 2026-01-21 | Verified Push notifications (OneSignal) for Desktop already implemented: useOneSignal hook, onesignal service with full API, user sync on auth, foreground/click handlers, tags for segmentation |
| 2.9 | 2026-01-21 | Added Crash reporting (Sentry) for Desktop: @sentry/react for frontend with dynamic loading, sentry-rs for Rust backend, ErrorBoundary integration, sensitive data filtering, environment-aware sampling, breadcrumbs for debugging |
| 2.8 | 2026-01-21 | Added Deep link handling for Desktop: tauri-plugin-deep-link integration, securesharing:// URL scheme, useDeepLink hook with support for invite/share/recovery/file/folder actions, pending deep link handling for unauthenticated users |
| 2.7 | 2026-01-21 | Added Notification filtering for Desktop: filter dropdown in NotificationsDropdown to filter by type (all, shares received, shares accepted, recovery requests, system); filtered empty state with "Show all" button |
| 2.6 | 2026-01-21 | Added Secure clipboard for Desktop: useSecureClipboard hook with automatic clearing after timeout, different timeouts for passwords (30s), recovery keys (15s), share links (5m), general data (60s); clipboard state tracking for UI feedback |
| 2.5 | 2026-01-21 | Added Favorites for Desktop: favoritesStore with persisted Zustand store, FavoritesPage with full CRUD operations, star icons in list/grid views, toggle in context/dropdown menus, badge count in sidebar navigation |
| 2.4 | 2026-01-21 | Added auto-lock timeout for Desktop: useIdleDetector hook tracks mouse/keyboard/touch activity, AutoLockProvider component, lock/updateLastActivity actions in authStore, window blur handling; updated UnlockScreen to conditionally show biometric |
| 2.3 | 2026-01-21 | Added keyboard shortcuts for Desktop: Navigation (Ctrl+1-4), file operations (Enter, Ctrl+D/U/O), selection (Ctrl+A, Esc), view modes (Ctrl+G/L), search (/), help (?); GlobalShortcuts component, enhanced KeyboardShortcutsDialog with 25+ shortcuts |
| 2.2 | 2026-01-21 | Added biometric unlock for Desktop: Windows Hello and Touch ID support with runtime availability detection via BiometricService, 6 new commands, useBiometric hook, conditional UI in Settings; updated status to 99% production-ready |
| 2.1 | 2026-01-21 | Added multi-tenant support for Desktop: tenant switching with TenantSwitcher UI, 11 new Tauri commands, tenantStore; updated command count to 61 across 8 modules |
| 2.0 | 2026-01-21 | Marked Desktop features as implemented: password change, edit profile, device enrollment/revocation, onboarding flow; updated Phase 2 with account management and onboarding milestones |
| 1.9 | 2026-01-21 | Updated Desktop column to reflect Tauri/Rust implementation; merged macOS/Windows into single Desktop (Tauri) column; marked 30+ features as implemented; updated Phase 2 as core complete; updated platform notes with actual tech stack |
| 1.8 | 2026-01-20 | Added macOS column (📋 planned); split Desktop into macOS and Windows; added macOS-specific features (Menu Bar, Drag-Drop, Keyboard shortcuts); added Phase 2 for macOS development |
| 1.7 | 2026-01-20 | Marked deep link handling as implemented for iOS; Phase 1.5 iOS Feature Parity now complete |
| 1.6 | 2026-01-20 | Added notification read tracking to iOS app with Core Data persistence, Combine publishers, dedicated Notifications tab with unread badge, date-based grouping, swipe actions |
| 1.5 | 2026-01-20 | Added tenant switching to iOS app |
| 1.4 | 2026-01-20 | Added Sentry crash reporting to iOS app |
| 1.3 | 2026-01-20 | Updated iOS column - marked 40+ features as implemented; added iOS-specific pending section for tenant switching, deep links, notification tracking, Sentry |
| 1.2 | 2026-01-20 | Moved biometric, auto-lock, search, share intent to implemented; added invitation, sorting, view modes, deep links, file preview, cache management, notification filtering, theming, onboarding |
| 1.1 | 2026-01-18 | Added: push notifications, local caching, bulk operations, favorites, notification read tracking, email notifications, crash reporting |
| 1.0 | 2026-01-18 | Initial feature roadmap |
