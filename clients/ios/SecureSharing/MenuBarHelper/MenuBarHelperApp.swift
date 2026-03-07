import SwiftUI

@main
struct MenuBarHelperApp: App {

    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Label("SecureSharing", systemImage: "lock.shield")
        }
        .menuBarExtraStyle(.window)
    }
}
