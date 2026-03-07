import UIKit

#if targetEnvironment(macCatalyst)
extension BaseViewController {

    /// Configure view controller for Mac Catalyst environment
    func configureForCatalyst() {
        // Adjust content insets for larger screens
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    }
}
#endif
