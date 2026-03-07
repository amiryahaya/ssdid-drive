import UIKit
import Combine

/// Delegate for onboarding view controller events
protocol OnboardingViewControllerDelegate: AnyObject {
    func onboardingViewControllerDidComplete()
}

/// Onboarding view controller with page carousel
final class OnboardingViewController: BaseViewController {

    weak var delegate: OnboardingViewControllerDelegate?

    // MARK: - Properties

    private let viewModel: OnboardingViewModel

    // MARK: - UI Components

    private lazy var scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = self
        return scroll
    }()

    private lazy var pageStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        return stack
    }()

    private lazy var pageControl: UIPageControl = {
        let control = UIPageControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.currentPageIndicatorTintColor = .systemBlue
        control.pageIndicatorTintColor = .systemGray4
        control.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        return control
    }()

    private lazy var skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Skip", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.accessibilityLabel = "Skip onboarding"
        button.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        return button
    }()

    private lazy var nextButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Next", for: .normal)
        button.applyPrimaryStyle()
        button.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Initialization

    init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(scrollView)
        view.addSubview(pageControl)
        view.addSubview(skipButton)
        view.addSubview(nextButton)

        scrollView.addSubview(pageStackView)

        setupPages()

        pageControl.numberOfPages = viewModel.pages.count
        pageControl.currentPage = 0

        NSLayoutConstraint.activate([
            // Skip button
            skipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // Scroll view
            scrollView.topAnchor.constraint(equalTo: skipButton.bottomAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -24),

            // Page stack view
            pageStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            pageStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            pageStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            pageStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            pageStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            // Page control
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -24),

            // Next button
            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            nextButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func setupPages() {
        for page in viewModel.pages {
            let pageView = createPageView(for: page)
            pageStackView.addArrangedSubview(pageView)

            NSLayoutConstraint.activate([
                pageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
            ])
        }
    }

    private func createPageView(for page: OnboardingPage) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: page.icon)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 80, weight: .regular)
        )
        iconView.tintColor = systemColor(from: page.color)
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = page.title
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.text = page.description
        descriptionLabel.font = .systemFont(ofSize: 17)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0

        container.isAccessibilityElement = true
        container.accessibilityLabel = "\(page.title). \(page.description)"

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(descriptionLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -100),
            iconView.widthAnchor.constraint(equalToConstant: 120),
            iconView.heightAnchor.constraint(equalToConstant: 120),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            descriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
        ])

        return container
    }

    private func systemColor(from name: String) -> UIColor {
        switch name {
        case "systemBlue": return .systemBlue
        case "systemPurple": return .systemPurple
        case "systemGreen": return .systemGreen
        case "systemOrange": return .systemOrange
        default: return .systemBlue
        }
    }

    override func setupBindings() {
        viewModel.$currentPage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] page in
                guard let self = self else { return }
                self.pageControl.currentPage = page

                let offset = CGFloat(page) * self.scrollView.bounds.width
                self.scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)

                self.updateButtons()
            }
            .store(in: &cancellables)
    }

    private func updateButtons() {
        if viewModel.isLastPage {
            nextButton.setTitle("Get Started", for: .normal)
            skipButton.isHidden = true
        } else {
            nextButton.setTitle("Next", for: .normal)
            skipButton.isHidden = false
        }
    }

    // MARK: - Actions

    @objc private func nextTapped() {
        triggerHapticFeedback()
        viewModel.nextPage()
    }

    @objc private func skipTapped() {
        triggerSelectionFeedback()
        viewModel.skipToEnd()
    }

    @objc private func pageControlChanged() {
        viewModel.goToPage(pageControl.currentPage)
    }
}

// MARK: - UIScrollViewDelegate

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.bounds.width)
        viewModel.goToPage(page)
    }
}
