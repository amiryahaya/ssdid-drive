import UIKit

/// Cell for displaying a PII conversation in the list
final class ConversationCell: UITableViewCell {

    // MARK: - Constants

    static let reuseIdentifier = "ConversationCell"

    // MARK: - UI Components

    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()

    private let providerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        return stack
    }()

    private let providerBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.backgroundColor = .tertiarySystemFill
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.textAlignment = .center
        return label
    }()

    private let modelLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        return label
    }()

    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        return label
    }()

    private let kemStatusView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemGreen
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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
        accessoryType = .disclosureIndicator

        contentView.addSubview(containerStack)
        contentView.addSubview(kemStatusView)

        containerStack.addArrangedSubview(titleLabel)
        containerStack.addArrangedSubview(providerStack)
        containerStack.addArrangedSubview(dateLabel)

        providerStack.addArrangedSubview(providerBadge)
        providerStack.addArrangedSubview(modelLabel)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            containerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerStack.trailingAnchor.constraint(equalTo: kemStatusView.leadingAnchor, constant: -12),
            containerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            kemStatusView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            kemStatusView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            kemStatusView.widthAnchor.constraint(equalToConstant: 20),
            kemStatusView.heightAnchor.constraint(equalToConstant: 20),

            providerBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    // MARK: - Configuration

    func configure(with conversation: PiiConversation) {
        titleLabel.text = conversation.title ?? NSLocalizedString("pii.chat.untitled", value: "Untitled Chat", comment: "Untitled conversation")

        // Provider badge
        let providerName = LlmProvider.provider(for: conversation.llmProvider)?.name ?? conversation.llmProvider
        providerBadge.text = "  \(providerName)  "

        // Model label
        modelLabel.text = conversation.llmModel

        // Date formatting
        dateLabel.text = formatDate(conversation.createdAt)

        // KEM status
        if conversation.hasKemKeysRegistered {
            kemStatusView.image = UIImage(systemName: "checkmark.shield.fill")
            kemStatusView.tintColor = .systemGreen
        } else {
            kemStatusView.image = UIImage(systemName: "shield")
            kemStatusView.tintColor = .tertiaryLabel
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: dateString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else {
                return dateString
            }
            return formatRelativeDate(date)
        }

        return formatRelativeDate(date)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        providerBadge.text = nil
        modelLabel.text = nil
        dateLabel.text = nil
        kemStatusView.image = nil
    }
}
