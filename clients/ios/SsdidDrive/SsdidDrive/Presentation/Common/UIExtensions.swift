import UIKit

// MARK: - UIButton Extensions

extension UIButton {

    /// Apply primary button style (filled blue background)
    func applyPrimaryStyle() {
        backgroundColor = .systemBlue
        setTitleColor(.white, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        layer.cornerRadius = 12
        clipsToBounds = true
    }

    /// Apply secondary button style (outlined)
    func applySecondaryStyle() {
        backgroundColor = .clear
        setTitleColor(.systemBlue, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        layer.cornerRadius = 12
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.systemBlue.cgColor
    }

    /// Apply destructive button style (red)
    func applyDestructiveStyle() {
        backgroundColor = .systemRed
        setTitleColor(.white, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        layer.cornerRadius = 12
        clipsToBounds = true
    }
}

// MARK: - UITextField Extensions

extension UITextField {

    /// Apply SsdidDrive text field style
    func applySsdidDriveStyle() {
        backgroundColor = .systemGray6
        layer.cornerRadius = 12
        layer.borderWidth = 0
        font = .systemFont(ofSize: 16)

        // Add padding
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: frame.height))
        leftView = paddingView
        leftViewMode = .always

        let rightPaddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: frame.height))
        rightView = rightPaddingView
        rightViewMode = .always
    }
}

// MARK: - UIView Extensions

extension UIView {

    /// Add shadow to view
    func addShadow(radius: CGFloat = 8, opacity: Float = 0.1, offset: CGSize = CGSize(width: 0, height: 2)) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.masksToBounds = false
    }

    /// Round specific corners
    func roundCorners(_ corners: UIRectCorner, radius: CGFloat) {
        let path = UIBezierPath(
            roundedRect: bounds,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        layer.mask = mask
    }

    /// Shake animation for errors
    func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.5
        animation.values = [-20, 20, -15, 15, -10, 10, -5, 5, 0]
        layer.add(animation, forKey: "shake")
    }
}

// MARK: - UIColor Extensions

extension UIColor {

    /// Convenience initializer for hex colors
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// MARK: - UIImage Extensions

extension UIImage {

    /// Resize image to specified size
    func resized(to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Create image from color
    static func from(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - String Extensions

extension String {

    /// Validate email format
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }

    /// Truncate string with ellipsis
    func truncated(to length: Int, trailing: String = "...") -> String {
        if count > length {
            return String(prefix(length)) + trailing
        }
        return self
    }
}

// MARK: - Date Extensions

extension Date {

    /// Format date as relative string (e.g., "2 hours ago")
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Format date as short string (e.g., "Jan 15")
    var shortString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

// MARK: - Data Extensions

extension Data {

    /// Convert to hex string
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize from hex string
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex

        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}

