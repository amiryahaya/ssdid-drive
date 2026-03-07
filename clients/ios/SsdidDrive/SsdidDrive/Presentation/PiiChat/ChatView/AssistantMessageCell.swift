import UIKit

/// Cell for displaying assistant messages
final class AssistantMessageCell: UITableViewCell {

    // MARK: - Constants

    static let reuseIdentifier = "AssistantMessageCell"

    // MARK: - UI Components

    private let avatarView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemFill
        view.layer.cornerRadius = 16
        view.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.image = UIImage(systemName: "cpu")
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])

        return view
    }()

    private let bubbleView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMinYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let piiCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(avatarView)
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(messageLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(piiCountLabel)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 8),
            bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -80),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),

            timeLabel.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            piiCountLabel.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            piiCountLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 8)
        ])
    }

    // MARK: - Configuration

    func configure(with message: ChatMessage) {
        messageLabel.text = message.content
        timeLabel.text = formatTime(message.createdAt)

        if message.tokensDetected > 0 {
            piiCountLabel.text = "\(message.tokensDetected) PII protected"
            piiCountLabel.isHidden = false
        } else {
            piiCountLabel.isHidden = true
        }

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "Assistant: \(message.content)"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        messageLabel.text = nil
        timeLabel.text = nil
        piiCountLabel.text = nil
        piiCountLabel.isHidden = true
    }
}
