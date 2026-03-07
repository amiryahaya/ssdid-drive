# macOS Feature Coverage Analysis

**Date:** January 20, 2026
**Purpose:** Cross-reference macOS implementation plan against features.md to ensure feature parity

---

## Feature Coverage Matrix

### Legend
- ✅ Covered in plan (via iOS code reuse)
- 🔧 Needs macOS-specific implementation
- ⚠️ Missing from plan - needs to be added
- ❌ Not applicable to macOS

---

## Core Features (from features.md)

| # | Feature | Android | iOS | macOS Plan | Notes |
|---|---------|:-------:|:---:|:----------:|-------|
| 1 | User registration with PQC key generation | ✅ | ✅ | ✅ | Reuse Crypto layer |
| 2 | Invitation-based registration | ✅ | ✅ | ✅ | Reuse Auth flow |
| 3 | Login with key derivation | ✅ | ✅ | ✅ | Reuse Auth flow |
| 4 | Multi-tenant support | ✅ | ✅ | ✅ | Reuse Tenant repository |
| 5 | Tenant switching | ✅ | ✅ | ✅ | Reuse Tenant UI |
| 6 | File browser with folders | ✅ | ✅ | ✅ | Reuse Files UI |
| 7 | File upload with encryption | ✅ | ✅ | ✅ | Reuse + drag-drop |
| 8 | File download with decryption | ✅ | ✅ | ✅ | Reuse + Finder integration |
| 9 | File preview (text, images, PDF, video) | ✅ | ✅ | ✅ | Reuse preview VCs |
| 10 | File rename/move/copy | ✅ | ✅ | ✅ | Reuse file operations |
| 11 | File/folder sharing | ✅ | ✅ | ✅ | Reuse Share UI |
| 12 | Share permissions (view/edit/download) | ✅ | ✅ | ✅ | Reuse Share UI |
| 13 | Share expiration | ✅ | ✅ | ✅ | Reuse Share UI |
| 14 | Received/Created shares view | ✅ | ✅ | ✅ | Reuse Shares tab |
| 15 | Share accept/decline/revoke | ✅ | ✅ | ✅ | Reuse Share actions |
| 16 | Shamir recovery system | ✅ | ✅ | ✅ | Reuse Recovery flow |
| 17 | Recovery setup (threshold config) | ✅ | ✅ | ✅ | Reuse Recovery UI |
| 18 | Trustee selection | ✅ | ✅ | ✅ | Reuse Recovery UI |
| 19 | Recovery initiation | ✅ | ✅ | ✅ | Reuse Recovery flow |
| 20 | Recovery approval (trustee) | ✅ | ✅ | ✅ | Reuse Recovery flow |
| 21 | Device enrollment | ✅ | ✅ | ✅ | Reuse Device management |
| 22 | Device list/revocation | ✅ | ✅ | ✅ | Reuse Device UI |
| 23 | Biometric unlock | ✅ | ✅ | 🔧 | Touch ID via LocalAuthentication |
| 24 | Auto-lock timeout | ✅ | ✅ | ✅ | Reuse lock mechanism |
| 25 | Screenshot prevention | ✅ | ✅ | 🔧 | Different on macOS (limited) |
| 26 | Secure clipboard | ✅ | ✅ | 🔧 | NSPasteboard differences |
| 27 | Push notifications (OneSignal) | ✅ | ✅ | 🔧 | OneSignal macOS SDK |
| 28 | Local database caching | ✅ | ✅ | ✅ | Reuse Core Data |
| 29 | Offline mode with sync | ✅ | ✅ | ✅ | Reuse sync logic |
| 30 | File search | ✅ | ✅ | ✅ | Reuse search + Spotlight? |
| 31 | Multi-select / bulk operations | ✅ | ✅ | ✅ | Reuse + keyboard modifiers |
| 32 | Favorites | ✅ | ✅ | ✅ | Reuse Favorites |
| 33 | Sorting (name, date, size, type) | ✅ | ✅ | ✅ | Reuse sorting |
| 34 | View modes (list/grid) | ✅ | ✅ | ✅ | Reuse view modes |
| 35 | Share extension | ✅ | ✅ | 🔧 | macOS Share Extension target |
| 36 | Deep link handling | ✅ | ✅ | 🔧 | URL scheme + Universal Links |
| 37 | Notification read tracking | ✅ | ✅ | ✅ | Reuse Notification repository |
| 38 | Notification filtering | ✅ | ✅ | ✅ | Reuse Notification UI |
| 39 | Cache management | ✅ | ✅ | ✅ | Reuse cache manager |
| 40 | Crash reporting (Sentry) | ✅ | ✅ | 🔧 | Sentry macOS SDK |
| 41 | Password change | ✅ | ✅ | ✅ | Reuse Settings |
| 42 | Edit profile | ✅ | ✅ | ✅ | Reuse Settings |
| 43 | Settings screens | ✅ | ✅ | ✅ | Reuse + Preferences window |
| 44 | Dark mode / theming | ✅ | ✅ | ✅ | System appearance (automatic) |
| 45 | Onboarding flow | ✅ | ✅ | ✅ | Reuse onboarding |
| 46 | File Provider extension | N/A | ✅ | 🔧 | Finder integration (in plan) |

---

## macOS-Specific Features

| Feature | In Plan | Priority | Notes |
|---------|:-------:|:--------:|-------|
| **Menu Bar App** | ✅ | Required | Sync status, quick upload, recent files |
| **File Provider (Finder)** | ✅ | Required | On-demand download, sync badges |
| **Keyboard Shortcuts** | ✅ | Required | Cmd+N, Cmd+U, Cmd+L, etc. |
| **Multi-window Support** | ✅ | Medium | UIKit scene-based |
| **Toolbar** | ✅ | Medium | NSToolbar integration |
| **Touch Bar** | ✅ | Low | Optional hardware support |
| **Drag and Drop** | ⚠️ | High | **Missing - need to add** |
| **Spotlight Integration** | ⚠️ | Medium | **Missing - consider adding** |
| **Quick Look Preview** | ⚠️ | Medium | **Missing - consider adding** |
| **Services Menu** | ⚠️ | Low | **Missing - optional** |
| **Handoff with iOS** | ⚠️ | Low | **Missing - optional** |

---

## Gap Analysis

### Missing from Current Plan (Must Add)

#### 1. Drag and Drop Support
**Priority: High**

macOS users expect drag-and-drop for file operations:
- Drag files from Finder into app to upload
- Drag files from app to Finder to download/export
- Drag files between folders within app
- Drag to share (drop on contact)

**Implementation:**
```swift
// In file browser view controller
extension FileBrowserViewController: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction,
                         canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: URL.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction,
                         performDrop session: UIDropSession) {
        session.loadObjects(ofClass: URL.self) { urls in
            // Upload dropped files
            self.uploadFiles(urls as! [URL])
        }
    }
}
```

#### 2. Deep Link Handling (macOS)
**Priority: High**

Handle URL schemes and Universal Links on macOS:
- `securesharing://invite/{token}`
- `securesharing://share/{id}`
- `https://securesharing.app/invite/{token}`

**Implementation:**
```swift
// In AppDelegate or SceneDelegate
#if targetEnvironment(macCatalyst)
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url else { return }
    DeepLinkHandler.shared.handle(url)
}
#endif
```

### Should Add (Recommended)

#### 3. Spotlight Integration
**Priority: Medium**

Index encrypted file metadata for Spotlight search:
- File names (not content - zero-knowledge)
- Last modified dates
- File types

**Implementation:**
- Use Core Spotlight framework
- Index on file sync
- Clear index on logout

#### 4. Quick Look Preview
**Priority: Medium**

Enable spacebar preview in Finder for SecureSharing files:
- Requires Quick Look extension
- Decrypt on-demand for preview
- Works with File Provider

---

## Updated Implementation Phases

### Phase 1: Foundation (Week 1-2)
- [x] Set up macOS Catalyst project
- [x] Build KAZ-KEM/KAZ-SIGN for macOS
- [x] Symlink iOS source code
- [ ] **Add: Configure drag-and-drop support**

### Phase 2: Core Adaptation (Week 3-4)
- [x] Window management
- [x] Keyboard shortcuts
- [x] Menu bar integration
- [ ] **Add: Drag-and-drop upload/download**
- [ ] **Add: Deep link URL scheme handling**

### Phase 3: Menu Bar Helper (Week 5)
- [x] Sync status
- [x] Recent files
- [x] Quick upload
- No changes

### Phase 4: File Provider (Week 6-8)
- [x] Finder integration
- [x] On-demand download
- [ ] **Add: Quick Look extension (optional)**
- [ ] **Add: Spotlight indexing (optional)**

### Phase 5: Polish (Week 9-10)
- [x] Accessibility
- [x] Performance
- [ ] **Add: Handoff support (optional)**
- [ ] **Add: Services menu (optional)**

---

## macOS-Specific Considerations

### Screenshot Prevention (Limited on macOS)

Unlike iOS, macOS has limited screenshot prevention:
- Cannot prevent system screenshots (Cmd+Shift+3/4)
- Can detect screenshot notifications
- Can watermark content as deterrent
- Consider: Warn user, log event, add watermark

```swift
#if targetEnvironment(macCatalyst)
// Listen for screenshot notifications
NotificationCenter.default.addObserver(
    forName: NSApplication.userDidTakeScreenCaptureNotification,
    object: nil,
    queue: .main
) { _ in
    // Log event, show warning
    AuditLogger.shared.logScreenshot()
}
#endif
```

### Secure Clipboard (macOS differences)

macOS clipboard works differently:
- NSPasteboard vs UIPasteboard
- Can set expiration via Catalyst bridge
- Clear on app backgrounding

```swift
#if targetEnvironment(macCatalyst)
class SecureClipboard {
    static func copy(_ text: String, expireAfter seconds: TimeInterval = 60) {
        UIPasteboard.general.string = text

        // Schedule clearing
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if UIPasteboard.general.string == text {
                UIPasteboard.general.string = ""
            }
        }
    }
}
#endif
```

### Push Notifications (OneSignal macOS)

OneSignal supports macOS:
- Use OneSignal macOS SDK (separate from iOS)
- Requires Apple Push Notification service (APNs) for macOS
- Same OneSignal app ID works

```swift
// In AppDelegate
#if targetEnvironment(macCatalyst)
import OneSignal

func applicationDidFinishLaunching(_ notification: Notification) {
    OneSignal.initWithLaunchOptions(nil)
    OneSignal.setAppId("YOUR_ONESIGNAL_APP_ID")
}
#endif
```

---

## Summary

### Features Fully Covered (via iOS reuse): 39/46 (85%)

All core functionality reuses iOS code via Mac Catalyst.

### Features Needing macOS-Specific Work: 7/46 (15%)

| Feature | Effort |
|---------|--------|
| Biometric (Touch ID) | Low - LocalAuthentication works |
| Screenshot prevention | Low - Limited, add watermark |
| Secure clipboard | Low - Minor API differences |
| Push notifications | Medium - OneSignal macOS SDK |
| Share extension | Medium - Separate target |
| Deep link handling | Low - URL scheme config |
| File Provider | High - Already planned |

### Missing Features to Add to Plan: 4

| Feature | Priority | Effort |
|---------|----------|--------|
| **Drag and Drop** | High | Medium |
| **Deep Links** | High | Low |
| Spotlight Integration | Medium | Medium |
| Quick Look Extension | Medium | High |

---

## Recommendation

Update the macOS implementation plan to include:

1. **Drag and Drop** - Essential for macOS UX (add to Phase 2)
2. **Deep Links** - Required for invitations/shares (add to Phase 2)
3. **Spotlight** - Nice to have (add to Phase 4 or defer)
4. **Quick Look** - Nice to have (add to Phase 4 or defer)

With these additions, the macOS app will have full feature parity with iOS.
