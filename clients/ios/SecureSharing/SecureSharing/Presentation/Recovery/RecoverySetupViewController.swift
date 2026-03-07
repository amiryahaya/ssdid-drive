import UIKit
import Combine

/// Recovery setup view controller
final class RecoverySetupViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: RecoverySetupViewModel

    // MARK: - UI Components

    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var headerImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "shield.checkered")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Set Up Account Recovery"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Social recovery allows trusted contacts to help you regain access to your account if you lose your password."
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var thresholdCard: SettingCardView = {
        let card = SettingCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.configure(
            title: "Recovery Threshold",
            description: "Minimum trustees needed to recover",
            onIncrement: { [weak self] in self?.viewModel.incrementThreshold() },
            onDecrement: { [weak self] in self?.viewModel.decrementThreshold() }
        )
        return card
    }()

    private lazy var sharesCard: SettingCardView = {
        let card = SettingCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.configure(
            title: "Total Trustees",
            description: "Number of people to distribute shares to",
            onIncrement: { [weak self] in self?.viewModel.incrementShares() },
            onDecrement: { [weak self] in self?.viewModel.decrementShares() }
        )
        return card
    }()

    private lazy var explanationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var proceedButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Choose Trustees", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(proceedTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: RecoverySetupViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Recovery Setup"

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        contentView.addSubview(headerImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)
        contentView.addSubview(thresholdCard)
        contentView.addSubview(sharesCard)
        contentView.addSubview(explanationLabel)
        contentView.addSubview(proceedButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            headerImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            headerImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            headerImageView.widthAnchor.constraint(equalToConstant: 80),
            headerImageView.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: headerImageView.bottomAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            thresholdCard.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 32),
            thresholdCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            thresholdCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            sharesCard.topAnchor.constraint(equalTo: thresholdCard.bottomAnchor, constant: 16),
            sharesCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            sharesCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            explanationLabel.topAnchor.constraint(equalTo: sharesCard.bottomAnchor, constant: 24),
            explanationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            explanationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            proceedButton.topAnchor.constraint(equalTo: explanationLabel.bottomAnchor, constant: 32),
            proceedButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            proceedButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            proceedButton.heightAnchor.constraint(equalToConstant: 52),
            proceedButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32)
        ])
    }

    override func setupBindings() {
        viewModel.$threshold
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.thresholdCard.updateValue(value)
                self?.updateExplanation()
            }
            .store(in: &cancellables)

        viewModel.$totalShares
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.sharesCard.updateValue(value)
                self?.updateExplanation()
            }
            .store(in: &cancellables)
    }

    private func updateExplanation() {
        explanationLabel.text = viewModel.explanation
        proceedButton.isEnabled = viewModel.isValid
        proceedButton.alpha = viewModel.isValid ? 1.0 : 0.5
    }

    // MARK: - Actions

    @objc private func proceedTapped() {
        triggerHapticFeedback()
        viewModel.proceedToTrusteeSelection()
    }
}

// MARK: - Setting Card View

final class SettingCardView: UIView {

    private var onIncrement: (() -> Void)?
    private var onDecrement: (() -> Void)?

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var valueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 32, weight: .bold)
        label.textColor = .systemBlue
        label.textAlignment = .center
        return label
    }()

    private lazy var decrementButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(decrementTapped), for: .touchUpInside)
        return button
    }()

    private lazy var incrementButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        button.tintColor = .systemBlue
        button.addTarget(self, action: #selector(incrementTapped), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .systemGray6
        layer.cornerRadius = 12

        addSubview(titleLabel)
        addSubview(descriptionLabel)
        addSubview(decrementButton)
        addSubview(valueLabel)
        addSubview(incrementButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            decrementButton.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -16),
            decrementButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            decrementButton.widthAnchor.constraint(equalToConstant: 44),
            decrementButton.heightAnchor.constraint(equalToConstant: 44),

            valueLabel.trailingAnchor.constraint(equalTo: incrementButton.leadingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 50),

            incrementButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            incrementButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            incrementButton.widthAnchor.constraint(equalToConstant: 44),
            incrementButton.heightAnchor.constraint(equalToConstant: 44),

            bottomAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 16)
        ])
    }

    func configure(title: String, description: String, onIncrement: @escaping () -> Void, onDecrement: @escaping () -> Void) {
        titleLabel.text = title
        descriptionLabel.text = description
        self.onIncrement = onIncrement
        self.onDecrement = onDecrement
    }

    func updateValue(_ value: Int) {
        valueLabel.text = "\(value)"
    }

    @objc private func incrementTapped() {
        onIncrement?()
    }

    @objc private func decrementTapped() {
        onDecrement?()
    }
}
