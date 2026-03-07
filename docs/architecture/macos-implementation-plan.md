# SecureSharing macOS App - Implementation Plan

**Version:** 1.1
**Date:** January 20, 2026
**Status:** Approved

---

## Executive Summary

This plan outlines the development of a macOS app for SecureSharing using **Mac Catalyst** to maximize UIKit code reuse from the existing iOS app. This approach provides the highest code reuse (estimated 80-90%) while still enabling macOS-specific features like Finder integration and menu bar access.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | **Mac Catalyst (UIKit)** | Maximum iOS code reuse |
| Menu Bar App | Required | Quick access, sync status |
| Finder Integration | Required | File Provider extension |
| Min Deployment | macOS 13 (Ventura) | Catalyst maturity, modern APIs |
| PQC Libraries | Copy from iOS | KAZ Swift bindings reusable |

---

## 1. Architecture: Mac Catalyst

### 1.1 What is Mac Catalyst?

Mac Catalyst allows iOS apps built with UIKit to run natively on macOS with minimal changes. The app is compiled for macOS but uses UIKit APIs, with automatic translation to AppKit under the hood.

### 1.2 Why Mac Catalyst for SecureSharing

| Benefit | Description |
|---------|-------------|
| **80-90% Code Reuse** | UIKit views, view controllers, coordinators all reusable |
| **Proven iOS Architecture** | MVVM + Coordinators already working |
| **Shared ViewModels** | Combine bindings work identically |
| **Same Navigation** | Coordinator pattern works on Catalyst |
| **Faster Development** | Much less code to write than native SwiftUI |

### 1.3 Catalyst Considerations

| Challenge | Solution |
|-----------|----------|
| Menu Bar App | Use AppKit via `#if targetEnvironment(macCatalyst)` |
| Finder Integration | File Provider extension (separate target, works with Catalyst) |
| macOS Look & Feel | Enable "Optimize for Mac" in build settings |
| Window Management | UIKit scene-based multi-window support |
| Keyboard Shortcuts | UIKeyCommand (already UIKit API) |

---

## 2. Code Reuse Analysis (Updated)

### 2.1 Reusability with Mac Catalyst

| Layer | iOS Files | Reusable | Notes |
|-------|-----------|:--------:|-------|
| **Domain/Model** | 9 files | 100% | Pure Swift |
| **Domain/Repository** | 6 files | 100% | Protocol definitions |
| **Data/Repository** | 6 files | 100% | URLSession-based |
| **Data/Local** | 4 files | 98% | Minor keychain access group changes |
| **Data/Remote** | 1 file | 100% | URLSession + SSL pinning |
| **Crypto** | 4 files | 100% | CryptoKit/CommonCrypto |
| **Crypto/PQC** | 4 files | 95% | Need macOS xcframework slice |
| **Core** | ~10 files | 100% | Constants, extensions, DI |
| **Presentation/Base** | 5 files | 100% | BaseViewController, BaseViewModel |
| **Presentation/ViewModels** | ~20 files | 100% | Combine-based, no UIKit deps |
| **Presentation/ViewControllers** | ~30 files | 90% | Minor adaptations needed |
| **Presentation/Coordinators** | ~8 files | 95% | Scene-based navigation |

**Total Estimated Reuse: 85-90%**

### 2.2 macOS-Specific Code Required

| Component | Effort | Notes |
|-----------|--------|-------|
| Menu Bar App | New | AppKit MenuBarExtra via plugin |
| File Provider Extension | New | Separate target, shared data layer |
| Catalyst Adaptations | Low | Conditional `#if targetEnvironment(macCatalyst)` |
| Window Management | Low | Multi-window scene support |
| Keyboard Shortcuts | Low | UIKeyCommand additions |
| Touch Bar (optional) | Low | NSTouchBar via Catalyst |

---

## 3. Project Structure

### 3.1 Updated Monorepo Structure

```
SecureSharing/
├── ios/
│   └── SecureSharing/                    # Existing iOS app
│       ├── SecureSharing/                # Main target
│       ├── SecureSharingTests/
│       ├── FileProviderExtension/        # iOS File Provider
│       └── ShareExtension/               # iOS Share Extension
│
├── macos/
│   └── SecureSharing/                    # macOS Catalyst app
│       ├── SecureSharing/                # Main Catalyst target
│       │   ├── macOS/                    # macOS-specific code
│       │   │   ├── MacCatalystBridge.swift
│       │   │   ├── MenuBarController.swift
│       │   │   ├── WindowManager.swift
│       │   │   └── KeyboardShortcuts.swift
│       │   └── Shared/                   # Symlinks to iOS code
│       │       ├── Core/ → ../../ios/.../Core
│       │       ├── Crypto/ → ../../ios/.../Crypto
│       │       ├── Domain/ → ../../ios/.../Domain
│       │       ├── Data/ → ../../ios/.../Data
│       │       └── Presentation/ → ../../ios/.../Presentation
│       ├── FileProviderExtension/        # macOS Finder integration
│       │   ├── FileProviderExtension.swift
│       │   ├── FileProviderItem.swift
│       │   ├── FileProviderEnumerator.swift
│       │   └── Info.plist
│       ├── MenuBarHelper/                # Menu bar app (AppKit)
│       │   ├── MenuBarApp.swift
│       │   ├── MenuBarView.swift
│       │   └── Info.plist
│       ├── SecureSharingTests/
│       └── project.yml                   # XcodeGen config
│
├── Shared/                               # Truly shared code (future)
│   ├── SecureSharingCore/                # Swift Package (optional)
│   └── SecureSharingCrypto/              # Swift Package (optional)
│
└── native/
    ├── kaz_kem/
    │   └── priv/
    │       └── KazKemNative.xcframework  # Add macOS slices
    └── kaz_sign/
        └── priv/
            └── KazSignNative.xcframework # Add macOS slices
```

### 3.2 Code Sharing Strategy

**Option A: Symlinks (Recommended for Speed)**
- Symlink iOS source folders into macOS project
- Use `#if targetEnvironment(macCatalyst)` for differences
- Single source of truth, changes reflect immediately

**Option B: Swift Packages (Future)**
- Extract shared code to local Swift Packages
- More setup but cleaner long-term
- Can do incrementally after V1

---

## 4. Mac Catalyst Configuration

### 4.1 Build Settings

```yaml
# project.yml (XcodeGen)
targets:
  SecureSharing:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: SecureSharing
      - path: Shared
    settings:
      SUPPORTS_MACCATALYST: YES
      DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER: NO
      PRODUCT_BUNDLE_IDENTIFIER: com.securesharing.macos
      SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
      # Optimize for Mac (native window chrome, etc.)
      CATALYST_INTERFACE_IDIOM: macOS
```

### 4.2 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- Network access -->
    <key>com.apple.security.network.client</key>
    <true/>

    <!-- Keychain sharing with iOS -->
    <key>com.apple.security.keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.securesharing</string>
    </array>

    <!-- File access -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>

    <!-- App Groups for File Provider -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.securesharing</string>
    </array>

    <!-- Hardened Runtime -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
</dict>
</plist>
```

### 4.3 Info.plist Additions

```xml
<!-- Enable multiple windows -->
<key>UIApplicationSupportsMultipleScenes</key>
<true/>

<!-- Mac Catalyst specific -->
<key>UIRequiresMacCatalyst</key>
<true/>

<!-- Minimum macOS version -->
<key>LSMinimumSystemVersion</key>
<string>13.0</string>
```

---

## 5. macOS-Specific Implementations

### 5.1 Menu Bar App

The Menu Bar app runs as a helper alongside the main app, providing quick access.

**Architecture:**
- Separate target (pure AppKit, not Catalyst)
- Communicates with main app via XPC or App Groups
- Shows sync status, recent files, quick upload

```swift
// MenuBarHelper/MenuBarApp.swift
import AppKit
import SwiftUI

@main
struct MenuBarHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("SecureSharing", systemImage: "lock.shield.fill") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarContentView: View {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sync status
            HStack {
                Image(systemName: viewModel.syncIcon)
                    .foregroundColor(viewModel.syncColor)
                Text(viewModel.syncStatus)
            }

            Divider()

            // Recent files
            Text("Recent Files")
                .font(.headline)
            ForEach(viewModel.recentFiles) { file in
                Button(file.name) {
                    viewModel.openFile(file)
                }
            }

            Divider()

            // Quick actions
            Button("Upload File...") {
                viewModel.uploadFile()
            }
            .keyboardShortcut("u", modifiers: .command)

            Button("Open SecureSharing") {
                viewModel.openMainApp()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
```

### 5.2 File Provider Extension (Finder Integration)

```swift
// FileProviderExtension/FileProviderExtension.swift
import FileProvider
import SecureSharingData  // Shared data layer

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    let domain: NSFileProviderDomain
    let cryptoManager: CryptoManager
    let apiClient: APIClient

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        // Initialize shared services from App Group
        let container = FileProviderContainer.shared
        self.cryptoManager = container.cryptoManager
        self.apiClient = container.apiClient
        super.init()
    }

    // MARK: - NSFileProviderReplicatedExtension

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        // Fetch item metadata from API or cache
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                let fileItem = try await fetchFileItem(identifier: identifier.rawValue)
                let providerItem = FileProviderItem(fileItem: fileItem)
                completionHandler(providerItem, nil)
            } catch {
                completionHandler(nil, error)
            }
            progress.completedUnitCount = 1
        }

        return progress
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        // Download and decrypt file
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                // Download encrypted file
                let encryptedData = try await apiClient.downloadFile(id: itemIdentifier.rawValue)
                progress.completedUnitCount = 50

                // Decrypt
                let decryptedData = try await cryptoManager.decrypt(encryptedData)
                progress.completedUnitCount = 80

                // Write to temporary location
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try decryptedData.write(to: tempURL)

                let item = try await fetchFileItem(identifier: itemIdentifier.rawValue)
                let providerItem = FileProviderItem(fileItem: item)

                completionHandler(tempURL, providerItem, nil)
                progress.completedUnitCount = 100
            } catch {
                completionHandler(nil, nil, error)
            }
        }

        return progress
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        // Upload and encrypt new file
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                guard let url = url else {
                    throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
                }

                // Read file
                let data = try Data(contentsOf: url)
                progress.completedUnitCount = 20

                // Encrypt
                let encryptedData = try await cryptoManager.encrypt(data)
                progress.completedUnitCount = 50

                // Upload
                let fileItem = try await apiClient.uploadFile(
                    name: itemTemplate.filename,
                    data: encryptedData,
                    parentId: itemTemplate.parentItemIdentifier.rawValue
                )
                progress.completedUnitCount = 90

                let providerItem = FileProviderItem(fileItem: fileItem)
                completionHandler(providerItem, [], false, nil)
                progress.completedUnitCount = 100
            } catch {
                completionHandler(nil, [], false, error)
            }
        }

        return progress
    }

    // ... other required methods
}
```

### 5.3 Drag and Drop Support

Essential for macOS user experience - upload files by dragging from Finder, download by dragging out.

```swift
// Presentation/Files/FileBrowserViewController+DragDrop.swift
import UIKit
import UniformTypeIdentifiers

#if targetEnvironment(macCatalyst)
extension FileBrowserViewController {

    func configureDragAndDrop() {
        // Enable drop to upload
        let dropInteraction = UIDropInteraction(delegate: self)
        view.addInteraction(dropInteraction)

        // Enable drag to export
        let dragInteraction = UIDragInteraction(delegate: self)
        dragInteraction.isEnabled = true
        tableView.addInteraction(dragInteraction)
    }
}

// MARK: - Drop to Upload
extension FileBrowserViewController: UIDropInteractionDelegate {

    func dropInteraction(_ interaction: UIDropInteraction,
                         canHandle session: UIDropSession) -> Bool {
        return session.canLoadObjects(ofClass: URL.self) ||
               session.hasItemsConforming(toTypeIdentifiers: [UTType.item.identifier])
    }

    func dropInteraction(_ interaction: UIDropInteraction,
                         sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction,
                         performDrop session: UIDropSession) {
        // Handle dropped files
        session.loadObjects(ofClass: URL.self) { [weak self] urls in
            guard let self = self, let fileURLs = urls as? [URL] else { return }

            // Upload each file
            for url in fileURLs {
                self.viewModel.uploadFile(from: url, to: self.currentFolder)
            }
        }
    }
}

// MARK: - Drag to Export
extension FileBrowserViewController: UIDragInteractionDelegate {

    func dragInteraction(_ interaction: UIDragInteraction,
                         itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let indexPath = tableView.indexPathForRow(at: session.location(in: tableView)),
              let file = viewModel.file(at: indexPath) else {
            return []
        }

        // Create drag item with file promise
        let itemProvider = NSItemProvider()
        itemProvider.registerFileRepresentation(
            forTypeIdentifier: UTType.item.identifier,
            visibility: .all
        ) { [weak self] completion in
            // Download and decrypt file for export
            Task {
                do {
                    let decryptedURL = try await self?.viewModel.downloadFileForExport(file)
                    completion(decryptedURL, true, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }

        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = file
        return [dragItem]
    }
}
#endif
```

### 5.4 Deep Link Handling

Handle URL schemes for invitations and share links on macOS.

```swift
// macOS/DeepLinkHandler.swift
import UIKit

#if targetEnvironment(macCatalyst)
extension SceneDelegate {

    func scene(_ scene: UIScene,
               openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleDeepLink(url)
    }

    func scene(_ scene: UIScene,
               continue userActivity: NSUserActivity) {
        // Handle Universal Links
        if let url = userActivity.webpageURL {
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Parse URL: securesharing://invite/{token}
        //            securesharing://share/{id}
        //            https://app.securesharing.com/invite/{token}

        guard let action = DeepLinkParser.parse(url) else { return }

        switch action {
        case .invitation(let token):
            coordinator?.handleInvitation(token: token)
        case .share(let shareId):
            coordinator?.openShare(id: shareId)
        case .file(let fileId):
            coordinator?.openFile(id: fileId)
        case .recovery(let requestId):
            coordinator?.openRecoveryRequest(id: requestId)
        }
    }
}
#endif

// Info.plist URL Schemes
/*
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.securesharing.macos</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>securesharing</string>
        </array>
    </dict>
</array>
*/
```

### 5.5 Keyboard Shortcuts

```swift
// macOS/KeyboardShortcuts.swift
import UIKit

extension AppDelegate {

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard builder.system == .main else { return }

        // File menu additions
        let uploadCommand = UIKeyCommand(
            title: "Upload File...",
            action: #selector(uploadFile),
            input: "U",
            modifierFlags: .command
        )

        let newFolderCommand = UIKeyCommand(
            title: "New Folder",
            action: #selector(createFolder),
            input: "N",
            modifierFlags: [.command, .shift]
        )

        let lockCommand = UIKeyCommand(
            title: "Lock App",
            action: #selector(lockApp),
            input: "L",
            modifierFlags: [.command, .control]
        )

        let fileMenu = UIMenu(
            title: "",
            options: .displayInline,
            children: [uploadCommand, newFolderCommand]
        )

        builder.insertChild(fileMenu, atStartOfMenu: .file)

        // App menu
        let appMenu = UIMenu(
            title: "",
            options: .displayInline,
            children: [lockCommand]
        )
        builder.insertSibling(appMenu, afterMenu: .about)
    }

    @objc func uploadFile() {
        NotificationCenter.default.post(name: .uploadFileRequested, object: nil)
    }

    @objc func createFolder() {
        NotificationCenter.default.post(name: .createFolderRequested, object: nil)
    }

    @objc func lockApp() {
        NotificationCenter.default.post(name: .lockAppRequested, object: nil)
    }
}
```

### 5.4 Window Management

```swift
// macOS/WindowManager.swift
import UIKit

#if targetEnvironment(macCatalyst)
class WindowManager {

    static let shared = WindowManager()

    func configureMainWindow(_ windowScene: UIWindowScene) {
        // Set minimum window size
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: .greatestFiniteMagnitude,
                                                           height: .greatestFiniteMagnitude)

        // Configure toolbar
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbarStyle = .unified

            let toolbar = NSToolbar(identifier: "MainToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            titlebar.toolbar = toolbar
        }
    }

    func openNewWindow(for activity: NSUserActivity) {
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil,
            errorHandler: nil
        )
    }
}

extension WindowManager: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        // Configure toolbar items
        switch itemIdentifier.rawValue {
        case "upload":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = UIImage(systemName: "arrow.up.doc")
            item.label = "Upload"
            item.action = #selector(AppDelegate.uploadFile)
            return item
        case "newFolder":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = UIImage(systemName: "folder.badge.plus")
            item.label = "New Folder"
            item.action = #selector(AppDelegate.createFolder)
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("upload"),
            NSToolbarItem.Identifier("newFolder"),
            .flexibleSpace,
            .searchField
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }
}
#endif
```

### 5.5 Catalyst-Specific UI Adaptations

```swift
// Presentation/Base/BaseViewController+Catalyst.swift
import UIKit

extension BaseViewController {

    func configureForkCatalyst() {
        #if targetEnvironment(macCatalyst)
        // Adjust content insets for larger screens
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        // Enable pointer interactions
        view.addInteraction(UIPointerInteraction(delegate: self))

        // Adjust font sizes for Mac
        // (handled automatically with Dynamic Type)
        #endif
    }
}

// MARK: - Pointer Interactions
extension BaseViewController: UIPointerInteractionDelegate {
    func pointerInteraction(_ interaction: UIPointerInteraction,
                            styleFor region: UIPointerRegion) -> UIPointerStyle? {
        return UIPointerStyle(effect: .highlight(UITargetedPreview(view: interaction.view!)))
    }
}
```

---

## 6. KAZ-KEM/KAZ-SIGN macOS Integration

### 6.1 Building Universal XCFrameworks

The existing iOS xcframeworks need macOS slices added:

```bash
#!/bin/bash
# build-macos-frameworks.sh

# Build KAZ-KEM for macOS
cd native/kaz_kem

# Build for macOS arm64
cargo build --release --target aarch64-apple-darwin

# Build for macOS x86_64
cargo build --release --target x86_64-apple-darwin

# Create macOS universal binary
lipo -create \
    target/aarch64-apple-darwin/release/libkaz_kem.a \
    target/x86_64-apple-darwin/release/libkaz_kem.a \
    -output target/libkaz_kem_macos.a

# Create universal xcframework (iOS + macOS)
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libkaz_kem.a \
    -headers include/ \
    -library target/aarch64-apple-ios-sim/release/libkaz_kem.a \
    -headers include/ \
    -library target/libkaz_kem_macos.a \
    -headers include/ \
    -output priv/KazKemNative.xcframework

# Repeat for KAZ-SIGN
cd ../kaz_sign
# ... similar commands
```

### 6.2 Swift Wrapper Updates

The existing iOS Swift wrappers should work with minimal changes:

```swift
// Crypto/PQC/KAZKEM.swift
import Foundation

public final class KAZKEM {

    public static func generateKeyPair() throws -> (publicKey: Data, secretKey: Data) {
        // Existing iOS code works on macOS via Catalyst
        var publicKeyLength: Int = 0
        var secretKeyLength: Int = 0

        kaz_kem_keypair_sizes(&publicKeyLength, &secretKeyLength)

        var publicKey = Data(count: publicKeyLength)
        var secretKey = Data(count: secretKeyLength)

        let result = publicKey.withUnsafeMutableBytes { pubPtr in
            secretKey.withUnsafeMutableBytes { secPtr in
                kaz_kem_keypair(pubPtr.baseAddress, secPtr.baseAddress)
            }
        }

        guard result == 0 else {
            throw CryptoError.keyGenerationFailed
        }

        return (publicKey, secretKey)
    }

    // ... rest of implementation unchanged
}
```

---

## 7. Implementation Phases

### Phase 1: Foundation (Week 1-2)

- [ ] Set up macOS Catalyst Xcode project
- [ ] Configure build settings and entitlements
- [ ] Build KAZ-KEM/KAZ-SIGN for macOS (universal xcframeworks)
- [ ] Symlink iOS source code into macOS project
- [ ] Verify compilation and basic launch
- [ ] Add `#if targetEnvironment(macCatalyst)` guards where needed

**Deliverable:** macOS app launches with iOS code running via Catalyst

### Phase 2: Core Adaptation (Week 3-4)

- [ ] Configure window management and sizing
- [ ] Add keyboard shortcuts (Cmd+N, Cmd+U, etc.)
- [ ] Implement macOS menu bar integration
- [ ] Add toolbar items
- [ ] Adapt navigation for larger screens
- [ ] Test all core flows (auth, files, sharing)

**Deliverable:** Fully functional Catalyst app with macOS conventions

### Phase 3: Menu Bar Helper (Week 5)

- [ ] Create MenuBarHelper target (AppKit)
- [ ] Implement sync status display
- [ ] Add recent files list
- [ ] Implement quick upload action
- [ ] Set up XPC/App Group communication with main app
- [ ] Auto-launch helper with main app

**Deliverable:** Working menu bar app with sync status and quick actions

### Phase 4: File Provider Extension (Week 6-8)

- [ ] Create FileProviderExtension target
- [ ] Implement NSFileProviderReplicatedExtension
- [ ] Set up domain registration
- [ ] Implement file enumeration
- [ ] Implement download (fetch + decrypt)
- [ ] Implement upload (encrypt + push)
- [ ] Add Finder context menu actions
- [ ] Test sync reliability and conflict resolution

**Deliverable:** Full Finder integration with on-demand download

### Phase 5: Polish and Release (Week 9-10)

- [ ] UI polish and Catalyst-specific refinements
- [ ] Accessibility audit
- [ ] Performance testing with large file sets
- [ ] Security review
- [ ] App Store screenshots and metadata
- [ ] TestFlight beta
- [ ] App Store submission

**Deliverable:** App Store-ready macOS app

---

## 8. Risk Assessment

### 8.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| KAZ-KEM macOS build fails | Low | High | Rust toolchain is cross-platform; fallback to ML-KEM |
| Catalyst UI quirks | Medium | Medium | Use `#if targetEnvironment` for specific fixes |
| File Provider complexity | High | Medium | Start simple, iterate; reference iOS File Provider |
| Menu Bar communication | Low | Low | Use App Groups (proven approach) |

### 8.2 Schedule Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| iOS regression from symlinks | Low | High | Comprehensive CI testing |
| File Provider takes longer | Medium | Medium | Can ship V1 without full Finder integration |
| App Store rejection | Low | Medium | Follow guidelines, sandbox properly |

---

## 9. Testing Strategy

### 9.1 Automated Tests

- Reuse iOS unit tests (should run on Catalyst)
- Add Catalyst-specific UI tests
- File Provider integration tests

### 9.2 Manual Testing

| Area | Test Cases |
|------|------------|
| Window Management | Resize, multiple windows, full screen |
| Keyboard Shortcuts | All shortcuts work, no conflicts |
| Menu Bar | Status updates, quick actions |
| Finder Integration | Browse, download, upload, rename, delete |
| Touch ID | Unlock with Touch ID |
| Drag and Drop | Files from Finder to app |

---

## 10. Success Metrics

| Metric | Target |
|--------|--------|
| Code Reuse | >85% from iOS |
| Development Time | 10 weeks |
| Crash-free Rate | >99.5% |
| App Store Rating | >4.5 stars |
| Finder Sync Reliability | >99% success |

---

## 11. Appendix

### A. Required Frameworks

| Framework | Purpose |
|-----------|---------|
| UIKit | Main UI (via Catalyst) |
| AppKit | Menu Bar Helper |
| FileProvider | Finder integration |
| CryptoKit | Encryption |
| Security | Keychain |
| LocalAuthentication | Touch ID |
| UserNotifications | Notifications |
| Combine | Reactive bindings |

### B. References

- [Mac Catalyst Documentation](https://developer.apple.com/mac-catalyst/)
- [Optimizing Your iPad App for Mac](https://developer.apple.com/documentation/uikit/mac_catalyst/optimizing_your_ipad_app_for_mac)
- [File Provider on macOS (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10182/)
- [Adding Menus and Shortcuts](https://developer.apple.com/documentation/uikit/uicommand/adding_menus_and_shortcuts_to_the_menu_bar_and_user_interface)
- [Menu Bar Extras (SwiftUI)](https://developer.apple.com/documentation/swiftui/menubarextra)

---

## Approval

**Prepared by:** Claude (System Architect)
**Date:** January 20, 2026

**User Decisions:**
- ✅ Menu Bar App: Required for V1
- ✅ Finder Integration: Required for V1
- ✅ Deployment Target: macOS 13 (Ventura)
- ✅ UI Framework: UIKit via Mac Catalyst
- ✅ PQC Libraries: Reuse KAZ Swift bindings from iOS

**Status:** Ready for Implementation
