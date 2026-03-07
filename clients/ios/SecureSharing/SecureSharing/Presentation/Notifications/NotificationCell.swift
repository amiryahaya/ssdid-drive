import UIKit

/// Table view cell for displaying a notification
final class NotificationCell: UITableViewCell {

    // MARK: - Constants

    static let reuseIdentifier = "NotificationCell"

    /// Static time formatter for today's notifications (e.g., "2:30 PM")
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// Static date formatter for older notifications (e.g., "Jan 15")
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    // MARK: - UI Components

    private lazy var iconContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 22
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.numberOfLines = 1
        return label
    }()

    private lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        return label
    }()

    private lazy var unreadIndicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBlue
        view.layer.cornerRadius = 5
        view.isHidden = true
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }()

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        iconContainerView.addSubview(iconView)
        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(messageLabel)

        contentView.addSubview(unreadIndicator)
        contentView.addSubview(iconContainerView)
        contentView.addSubview(contentStackView)
        contentView.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            // Unread indicator
            unreadIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            unreadIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            unreadIndicator.widthAnchor.constraint(equalToConstant: 10),
            unreadIndicator.heightAnchor.constraint(equalToConstant: 10),

            // Icon container
            iconContainerView.leadingAnchor.constraint(equalTo: unreadIndicator.trailingAnchor, constant: 8),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 44),
            iconContainerView.heightAnchor.constraint(equalToConstant: 44),

            // Icon inside container
            iconView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            // Time label
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80),

            // Content stack
            contentStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            contentStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 12),
            contentStackView.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
            contentStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        messageLabel.text = nil
        timeLabel.text = nil
        iconView.image = nil
        unreadIndicator.isHidden = true
        iconContainerView.backgroundColor = .systemGray
    }

    // MARK: - Configuration

    func configure(with notification: AppNotification) {
        titleLabel.text = notification.title
        messageLabel.text = notification.message
        timeLabel.text = formatTime(notification.createdAt)

        // Set icon
        iconView.image = UIImage(systemName: notification.type.icon)

        // Set icon container color directly from notification type
        iconContainerView.backgroundColor = notification.type.tintColor

        // Show unread indicator
        unreadIndicator.isHidden = notification.isRead

        // Update text color based on read status
        if notification.isRead {
            titleLabel.textColor = .secondaryLabel
            backgroundColor = .systemBackground
        } else {
            titleLabel.textColor = .label
            backgroundColor = .secondarySystemBackground.withAlphaComponent(0.5)
        }

        // Configure accessibility
        configureAccessibility(for: notification)
    }

    // MARK: - Accessibility

    private func configureAccessibility(for notification: AppNotification) {
        isAccessibilityElement = true
        accessibilityLabel = "\(notification.title). \(notification.message)"

        if notification.isUnread {
            accessibilityHint = NSLocalizedString(
                "accessibility.notification.unread",
                value: "Unread notification. Double tap to view.",
                comment: "Accessibility hint for unread notification"
            )
            accessibilityTraits = [.button]
        } else {
            accessibilityHint = NSLocalizedString(
                "accessibility.notification.read",
                value: "Double tap to view.",
                comment: "Accessibility hint for read notification"
            )
            accessibilityTraits = .button
        }

        // Add time as accessibility value
        accessibilityValue = formatTime(notification.createdAt)
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            // Show time for today (e.g., "2:30 PM")
            return Self.timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return NSLocalizedString("notification.time.yesterday", value: "Yesterday", comment: "Yesterday time label")
        } else {
            // Show date for older notifications (e.g., "Jan 15")
            return Self.dateFormatter.string(from: date)
        }
    }
}
