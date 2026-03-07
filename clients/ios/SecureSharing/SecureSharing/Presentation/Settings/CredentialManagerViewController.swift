import UIKit
import Combine

/// View controller for managing WebAuthn/OIDC credentials
final class CredentialManagerViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Properties

    private let viewModel: CredentialManagerViewModel

    // MARK: - UI Components

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "CredentialCell")
        return table
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No credentials registered yet."
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Initialization

    init(viewModel: CredentialManagerViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    override func setupUI() {
        title = "Security Keys & Passkeys"

        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func setupBindings() {
        viewModel.$credentials
            .receive(on: DispatchQueue.main)
            .sink { [weak self] credentials in
                self?.tableView.reloadData()
                self?.emptyLabel.isHidden = !credentials.isEmpty
                self?.tableView.isHidden = credentials.isEmpty
            }
            .store(in: &cancellables)

        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                if isLoading {
                    self?.activityIndicator.startAnimating()
                } else {
                    self?.activityIndicator.stopAnimating()
                }
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                if let message = message {
                    self?.showErrorAlert(message: message)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.credentials.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CredentialCell", for: indexPath)
        let credential = viewModel.credentials[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = credential.name ?? credential.credentialType

        var details = credential.credentialType
        if let provider = credential.providerName {
            details += " - \(provider)"
        }
        config.secondaryText = details

        let iconName = credential.credentialType == "webauthn" ? "person.badge.key.fill" : "globe"
        config.image = UIImage(systemName: iconName)
        config.imageProperties.tintColor = .systemBlue

        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let credential = viewModel.credentials[indexPath.row]
        showActionSheet(for: credential)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let credential = viewModel.credentials[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.confirmDelete(credential: credential)
            completion(true)
        }

        let rename = UIContextualAction(style: .normal, title: "Rename") { [weak self] _, _, completion in
            self?.showRenameAlert(for: credential)
            completion(true)
        }
        rename.backgroundColor = .systemBlue

        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    // MARK: - Actions

    private func showActionSheet(for credential: UserCredential) {
        let alert = UIAlertController(title: credential.name ?? credential.credentialType, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.showRenameAlert(for: credential)
        })

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDelete(credential: credential)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    private func showRenameAlert(for credential: UserCredential) {
        let alert = UIAlertController(title: "Rename Credential", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = credential.name
            textField.placeholder = "Credential name"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            self?.viewModel.renameCredential(id: credential.id, name: name)
        })
        present(alert, animated: true)
    }

    private func confirmDelete(credential: UserCredential) {
        let alert = UIAlertController(
            title: "Delete Credential",
            message: "Are you sure you want to delete this credential? This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteCredential(id: credential.id)
        })
        present(alert, animated: true)
    }

    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
