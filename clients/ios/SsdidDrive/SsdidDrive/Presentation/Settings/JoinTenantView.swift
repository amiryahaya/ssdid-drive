import SwiftUI

/// SwiftUI view for entering a short invite code to join a tenant (organization).
/// Supports both authenticated (settings) and unauthenticated (login) flows.
struct JoinTenantView: View {

    @ObservedObject var viewModel: JoinTenantViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerView

                    switch viewModel.state {
                    case .idle, .lookingUp, .error:
                        codeEntryView
                    case .preview, .joining:
                        previewCardView
                    case .success:
                        successView
                    }

                    if let error = viewModel.errorMessage {
                        errorView(message: error)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Join Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Enter Invite Code")
                .font(.title2)
                .fontWeight(.bold)

            Text("Enter the short code you received to join an organization.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Code Entry

    private var codeEntryView: some View {
        VStack(spacing: 16) {
            TextField("e.g. ACME-7K9X", text: $viewModel.code)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .accessibilityLabel("Invite code")
                .accessibilityHint("Enter the short invite code")
                .onChange(of: viewModel.code) { newValue in
                    viewModel.code = newValue.uppercased()
                }

            Button(action: {
                viewModel.lookUpCode()
            }) {
                HStack {
                    if viewModel.state == .lookingUp {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text("Look Up")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canLookUp ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
                .fontWeight(.semibold)
            }
            .disabled(!viewModel.canLookUp)
            .accessibilityLabel("Look up invite code")
        }
    }

    // MARK: - Preview Card

    private var previewCardView: some View {
        VStack(spacing: 20) {
            if let invitation = viewModel.invitation {
                // Invitation preview card
                VStack(spacing: 16) {
                    // Tenant avatar
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 64, height: 64)

                        Text(tenantInitials(invitation.tenantName))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                    }

                    // Tenant name
                    Text(invitation.tenantName)
                        .font(.title3)
                        .fontWeight(.bold)

                    // Role badge
                    HStack(spacing: 8) {
                        Text("Join as")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        RoleBadge(role: invitation.role)
                    }

                    // Expiry info
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Expires \(invitation.expiresAt.relativeString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Code shown
                    Text(invitation.shortCode)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(16)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        viewModel.acceptInvitation()
                    }) {
                        HStack {
                            if viewModel.state == .joining {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Join Organization")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .fontWeight(.semibold)
                    }
                    .disabled(viewModel.state == .joining)
                    .accessibilityLabel("Join \(invitation.tenantName)")

                    Button(action: {
                        viewModel.clearPreview()
                    }) {
                        Text("Enter a Different Code")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                    .disabled(viewModel.state == .joining)
                }
            }
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Welcome!")
                .font(.title2)
                .fontWeight(.bold)

            if let invitation = viewModel.invitation {
                Text("You've joined **\(invitation.tenantName)**.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 32)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Helpers

    private func tenantInitials(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Preview

#if DEBUG
struct JoinTenantView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Join Tenant Preview")
    }
}
#endif
