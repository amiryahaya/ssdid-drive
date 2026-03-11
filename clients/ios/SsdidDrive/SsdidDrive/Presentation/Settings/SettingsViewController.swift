import UIKit
import Combine

/// Settings view controller with grouped sections
final class SettingsViewController: BaseViewController {

    // MARK: - Properties

    private let viewModel: SettingsViewModel

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        table.register(SwitchCell.self, forCellReuseIdentifier: "SwitchCell")
        table.register(ProfileCell.self, forCellReuseIdentifier: "ProfileCell")
        table.register(TenantCell.self, forCellReuseIdentifier: "TenantCell")
        table.accessibilityIdentifier = "settingsTableView"
        return table
    }()

    // MARK: - Initialization

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.loadUser()
        viewModel.loadTenantContext()
    }

    // MARK: - Setup

    override func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        title = "Settings"

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func setupBindings() {
        viewModel.$user
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
            }
            .store(in: &cancellables)

        viewModel.$isBiometricEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
            }
            .store(in: &cancellables)

        viewModel.$isAutoLockEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadSections(IndexSet(integer: 2), with: .none)
            }
            .store(in: &cancellables)

        viewModel.$currentTenant
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Reload organization section (includes role-based items)
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    private func showAutoLockTimeoutPicker() {
        let alert = UIAlertController(title: "Auto-Lock Timeout", message: nil, preferredStyle: .actionSheet)

        let options = [1, 2, 5, 10, 15, 30]
        for minutes in options {
            let title = minutes == 1 ? "1 minute" : "\(minutes) minutes"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.viewModel.setAutoLockTimeout(minutes)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.bounds
        }

        present(alert, animated: true)
    }

    private func confirmLogout() {
        let alert = UIAlertController(
            title: "Log Out",
            message: "Are you sure you want to log out? You'll need to sign in again to access your files.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            self?.viewModel.logout()
        })

        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        SettingsViewModel.SettingsSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let settingsSection = SettingsViewModel.SettingsSection.allCases[section]
        return viewModel.items(for: settingsSection).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        SettingsViewModel.SettingsSection.allCases[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = SettingsViewModel.SettingsSection.allCases[indexPath.section]
        let item = viewModel.items(for: section)[indexPath.row]

        switch item {
        case .profile:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath) as! ProfileCell
            cell.configure(with: viewModel.user)
            cell.accessoryType = .none
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "settingsProfileCell"
            return cell

        case .devices:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Devices"
            content.image = UIImage(systemName: "laptopcomputer.and.iphone")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "settingsDevicesCell"
            return cell

        case .invitations:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Invitations"
            content.image = UIImage(systemName: "envelope")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "settingsInvitationsCell"
            return cell

        case .invitationsList:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Invitations"
            content.secondaryText = "Received & sent"
            content.image = UIImage(systemName: "envelope")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "settingsInvitationsListCell"
            return cell

        case .createInvitation:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Create Invitation"
            content.secondaryText = "Invite someone to join"
            content.image = UIImage(systemName: "envelope.badge.person.crop")
            content.imageProperties.tintColor = .systemBlue
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "settingsCreateInvitationCell"
            return cell

        case .members:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Members"
            content.secondaryText = "View & manage members"
            content.image = UIImage(systemName: "person.3")
            content.imageProperties.tintColor = .systemBlue
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "settingsMembersCell"
            return cell

        case .tenant:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TenantCell", for: indexPath) as! TenantCell
            cell.configure(with: viewModel.currentTenant, tenantCount: viewModel.tenantCount)
            cell.accessoryType = viewModel.tenantCount > 1 ? .disclosureIndicator : .none
            cell.selectionStyle = viewModel.tenantCount > 1 ? .default : .none
            cell.accessibilityIdentifier = "settingsTenantCell"
            return cell

        case .joinTenant:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Join Organization"
            content.secondaryText = "Enter an invite code"
            content.image = UIImage(systemName: "person.badge.plus")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "settingsJoinTenantCell"
            return cell

        case .credentials:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Security Keys & Passkeys"
            content.image = UIImage(systemName: "key.fill")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "settingsCredentialsCell"
            return cell

        case .biometric:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchCell
            cell.configure(
                title: viewModel.biometricLabel,
                icon: viewModel.biometricType == .faceID ? "faceid" : "touchid",
                isOn: viewModel.isBiometricEnabled,
                accessibilityId: "settingsBiometricSwitch"
            ) { [weak self] isOn in
                self?.viewModel.setBiometricEnabled(isOn)
            }
            return cell

        case .autoLock:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SwitchCell", for: indexPath) as! SwitchCell
            cell.configure(
                title: "Auto-Lock",
                icon: "lock.fill",
                isOn: viewModel.isAutoLockEnabled,
                accessibilityId: "settingsAutoLockSwitch"
            ) { [weak self] isOn in
                self?.viewModel.setAutoLockEnabled(isOn)
            }
            return cell

        case .autoLockTimeout:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Lock After"
            content.secondaryText = viewModel.autoLockTimeout == 1 ? "1 minute" : "\(viewModel.autoLockTimeout) minutes"
            content.image = UIImage(systemName: "timer")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .recoverySetup:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Set Up Recovery"
            content.image = UIImage(systemName: "shield.checkered")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .trusteeDashboard:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Trustee Dashboard"
            content.image = UIImage(systemName: "person.2.fill")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .initiateRecovery:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Recover Account"
            content.image = UIImage(systemName: "arrow.counterclockwise")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .version:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Version"
            content.secondaryText = viewModel.appVersion
            content.image = UIImage(systemName: "info.circle")
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            cell.accessibilityIdentifier = "settingsVersionLabel"
            return cell

        case .privacy:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Privacy Policy"
            content.image = UIImage(systemName: "hand.raised")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .terms:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Terms of Service"
            content.image = UIImage(systemName: "doc.text")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .logout:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Log Out"
            content.textProperties.color = .systemRed
            content.image = UIImage(systemName: "rectangle.portrait.and.arrow.right")
            content.imageProperties.tintColor = .systemRed
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "settingsLogoutButton"
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        triggerSelectionFeedback()

        let section = SettingsViewModel.SettingsSection.allCases[indexPath.section]
        let item = viewModel.items(for: section)[indexPath.row]

        switch item {
        case .devices:
            viewModel.showDevices()
        case .invitations:
            viewModel.showInvitations()
        case .invitationsList:
            viewModel.showInvitationsList()
        case .createInvitation:
            viewModel.showCreateInvitation()
        case .members:
            viewModel.showMembers()
        case .credentials:
            viewModel.showCredentials()
        case .tenant:
            if viewModel.tenantCount > 1 {
                viewModel.showTenantSwitcher()
            }
        case .joinTenant:
            viewModel.showJoinTenant()
        case .autoLockTimeout:
            showAutoLockTimeoutPicker()
        case .recoverySetup:
            viewModel.showRecoverySetup()
        case .trusteeDashboard:
            viewModel.showTrusteeDashboard()
        case .initiateRecovery:
            viewModel.showInitiateRecovery()
        case .privacy:
            openURL("https://ssdid-drive.app/privacy")
        case .terms:
            openURL("https://ssdid-drive.app/terms")
        case .logout:
            confirmLogout()
        default:
            break
        }
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Switch Cell

final class SwitchCell: UITableViewCell {

    private var onToggle: ((Bool) -> Void)?

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17)
        return label
    }()

    private lazy var toggle: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        return toggle
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none

        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(toggle)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func configure(title: String, icon: String, isOn: Bool, accessibilityId: String? = nil, onToggle: @escaping (Bool) -> Void) {
        titleLabel.text = title
        iconImageView.image = UIImage(systemName: icon)
        toggle.isOn = isOn
        toggle.accessibilityLabel = title
        if let id = accessibilityId {
            toggle.accessibilityIdentifier = id
        }
        self.onToggle = onToggle

        // Let the toggle handle accessibility for the whole cell
        isAccessibilityElement = false
    }

    @objc private func toggleChanged() {
        onToggle?(toggle.isOn)
    }
}

// MARK: - Profile Cell

final class ProfileCell: UITableViewCell {

    private lazy var avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = .systemBlue
        imageView.tintColor = .white
        imageView.layer.cornerRadius = 30
        imageView.clipsToBounds = true
        imageView.contentMode = .center
        imageView.image = UIImage(systemName: "person.fill")
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        return label
    }()

    private lazy var emailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(emailLabel)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            avatarImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 60),
            avatarImageView.heightAnchor.constraint(equalToConstant: 60),

            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: 8),

            emailLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            emailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            emailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4)
        ])
    }

    func configure(with user: User?) {
        if let user = user {
            let name = user.email.components(separatedBy: "@").first?.capitalized ?? user.email
            nameLabel.text = name
            emailLabel.text = user.email

            isAccessibilityElement = true
            accessibilityLabel = "\(name), \(user.email)"
        } else {
            nameLabel.text = "Loading..."
            emailLabel.text = ""

            isAccessibilityElement = true
            accessibilityLabel = "Loading profile"
        }
    }
}

// MARK: - Tenant Cell

final class TenantCell: UITableViewCell {

    private lazy var iconContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        view.layer.cornerRadius = 8
        return view
    }()

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(systemName: "building.2.fill")
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17)
        return label
    }()

    private lazy var detailStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }()

    private lazy var roleBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        return label
    }()

    private lazy var countLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailStackView)
        detailStackView.addArrangedSubview(roleBadge)
        detailStackView.addArrangedSubview(countLabel)

        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconContainerView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 44),
            iconContainerView.heightAnchor.constraint(equalToConstant: 44),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            nameLabel.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            detailStackView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 12),
            detailStackView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            detailStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            roleBadge.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func configure(with tenant: Tenant?, tenantCount: Int) {
        if let tenant = tenant {
            nameLabel.text = tenant.name

            // Configure role badge
            roleBadge.text = "  \(tenant.role.displayName)  "
            switch tenant.role {
            case .admin:
                roleBadge.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.2)
                roleBadge.textColor = .systemPurple
            case .member:
                roleBadge.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
                roleBadge.textColor = .systemBlue
            case .viewer:
                roleBadge.backgroundColor = UIColor.systemGray.withAlphaComponent(0.2)
                roleBadge.textColor = .systemGray
            }
            roleBadge.isHidden = false

            // Show count if multiple tenants
            if tenantCount > 1 {
                countLabel.text = "\(tenantCount) organizations"
                countLabel.isHidden = false
            } else {
                countLabel.isHidden = true
            }
        } else {
            nameLabel.text = "Organization"
            roleBadge.isHidden = true
            countLabel.text = "Not selected"
            countLabel.isHidden = false
        }
    }
}
