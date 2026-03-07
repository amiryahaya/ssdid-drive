import UIKit

/// Delegate for message input bar events
protocol MessageInputBarDelegate: AnyObject {
    func messageInputBar(_ inputBar: MessageInputBar, didSendMessage text: String)
}

/// Input bar for composing and sending messages
final class MessageInputBar: UIView {

    // MARK: - Properties

    weak var delegate: MessageInputBarDelegate?
    var isSending: Bool = false {
        didSet {
            updateSendButton()
            textView.isEditable = !isSending
        }
    }

    // MARK: - UI Components

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 20
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.accessibilityLabel = "Message input"
        return textView
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("pii.chat.placeholder", value: "Type a message...", comment: "Message placeholder")
        label.font = .systemFont(ofSize: 16)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.contentVerticalAlignment = .fill
        button.contentHorizontalAlignment = .fill
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        button.accessibilityLabel = "Send message"
        return button
    }()

    private let securityIndicator: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "lock.fill")
        imageView.tintColor = .systemGreen
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private var textViewHeightConstraint: NSLayoutConstraint!
    private let maxTextViewHeight: CGFloat = 100

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .systemBackground

        addSubview(containerView)
        addSubview(sendButton)
        addSubview(securityIndicator)

        containerView.addSubview(textView)
        containerView.addSubview(placeholderLabel)

        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 40)

        NSLayoutConstraint.activate([
            securityIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            securityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            securityIndicator.widthAnchor.constraint(equalToConstant: 16),
            securityIndicator.heightAnchor.constraint(equalToConstant: 16),

            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: securityIndicator.trailingAnchor, constant: 8),
            containerView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            containerView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),

            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            textViewHeightConstraint,

            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),

            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        updateSendButton()
    }

    // MARK: - Actions

    @objc private func sendTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !isSending else { return }

        delegate?.messageInputBar(self, didSendMessage: text)
        textView.text = ""
        textViewDidChange(textView)
    }

    private func updateSendButton() {
        let hasText = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText && !isSending
        sendButton.alpha = (hasText && !isSending) ? 1.0 : 0.5

        if isSending {
            sendButton.setImage(UIImage(systemName: "hourglass"), for: .normal)
        } else {
            sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        }
    }

    private func updateTextViewHeight() {
        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(size.height, 40), maxTextViewHeight)
        textViewHeightConstraint.constant = newHeight
        textView.isScrollEnabled = newHeight >= maxTextViewHeight
    }

    // MARK: - Public Methods

    func clearText() {
        textView.text = ""
        textViewDidChange(textView)
    }
}

// MARK: - UITextViewDelegate

extension MessageInputBar: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendButton()
        updateTextViewHeight()
    }
}
