import UIKit

/// Custom table view cell for displaying a file activity log entry
final class ActivityCell: UITableViewCell {

    // MARK: - Constants

    static let reuseIdentifier = "ActivityCell"
    private let iconSize: CGFloat = 36

    // MARK: - UI Components

    private let iconContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 18
        view.clipsToBounds = true
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    private let timestampLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }()

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupCell() {
        iconContainer.addSubview(iconImageView)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        contentView.addSubview(iconContainer)
        contentView.addSubview(textStack)
        contentView.addSubview(timestampLabel)

        NSLayoutConstraint.activate([
            // Icon container
            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: iconSize),
            iconContainer.heightAnchor.constraint(equalToConstant: iconSize),

            // Icon image inside container
            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 18),
            iconImageView.heightAnchor.constraint(equalToConstant: 18),

            // Text stack
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            // Timestamp
            timestampLabel.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8),
            timestampLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timestampLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    // MARK: - Configuration

    func configure(with activity: FileActivity) {
        titleLabel.text = activity.eventLabel
        iconImageView.image = UIImage(systemName: activity.iconName)
        timestampLabel.text = activity.timeAgo

        // Build detail text
        var detail = activity.resourceName
        if let actorName = activity.actorName {
            detail += " \u{2022} \(actorName)"
        }
        detailLabel.text = detail

        // Set icon background color
        iconContainer.backgroundColor = iconColor(for: activity.iconColorName)
    }

    // MARK: - Helpers

    private func iconColor(for name: String) -> UIColor {
        switch name {
        case "systemBlue": return .systemBlue
        case "systemGreen": return .systemGreen
        case "systemRed": return .systemRed
        case "systemOrange": return .systemOrange
        case "systemPurple": return .systemPurple
        case "systemTeal": return .systemTeal
        case "systemIndigo": return .systemIndigo
        case "systemYellow": return .systemYellow
        default: return .systemGray
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        detailLabel.text = nil
        timestampLabel.text = nil
        iconImageView.image = nil
        iconContainer.backgroundColor = .systemGray
    }
}
