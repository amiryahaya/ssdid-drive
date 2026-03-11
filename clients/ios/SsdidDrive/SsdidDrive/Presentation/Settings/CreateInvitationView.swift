import SwiftUI

/// SwiftUI view for creating a new tenant invitation (Admin/Owner only)
struct CreateInvitationView: View {

    @ObservedObject var viewModel: CreateInvitationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerView

                    switch viewModel.state {
                    case .idle, .creating, .error:
                        formView
                    case .success:
                        successView
                    }

                    if let error = viewModel.errorMessage {
                        errorView(message: error)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Create Invitation")
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
            Image(systemName: "envelope.badge.person.crop")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Invite to Organization")
                .font(.title2)
                .fontWeight(.bold)

            Text("Create an invite code to share with someone.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Form

    private var formView: some View {
        VStack(spacing: 20) {
            // Email field (optional)
            VStack(alignment: .leading, spacing: 6) {
                Text("Email (optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("recipient@example.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .accessibilityLabel("Email address")

                if !viewModel.email.isEmpty && !viewModel.isEmailValid {
                    Text("Please enter a valid email address")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Role picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Role")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Role", selection: $viewModel.selectedRole) {
                    ForEach(viewModel.availableRoles, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Member role")
            }

            // Message field (optional)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Message (optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(viewModel.remainingCharacters)")
                        .font(.caption)
                        .foregroundColor(viewModel.remainingCharacters < 0 ? .red : .secondary)
                }

                TextEditor(text: $viewModel.message)
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .accessibilityLabel("Invitation message")
            }

            // Create button
            Button(action: {
                viewModel.createInvitation()
            }) {
                HStack {
                    if viewModel.state == .creating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text("Create Invitation")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canCreate ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
                .fontWeight(.semibold)
            }
            .disabled(!viewModel.canCreate)
            .accessibilityLabel("Create invitation")
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Invitation Created!")
                .font(.title2)
                .fontWeight(.bold)

            if let invitation = viewModel.createdInvitation {
                // Short code display
                VStack(spacing: 12) {
                    Text("Share this code:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(invitation.shortCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .accessibilityLabel("Invite code: \(invitation.shortCode)")

                    // Copy and Share buttons
                    HStack(spacing: 16) {
                        Button(action: {
                            UIPasteboard.general.string = invitation.shortCode
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                            .fontWeight(.medium)
                        }
                        .accessibilityLabel("Copy invite code")

                        ShareLink(
                            item: "Join my organization with code: \(invitation.shortCode)",
                            subject: Text("Organization Invite"),
                            message: Text("Use this code to join: \(invitation.shortCode)")
                        ) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                            .fontWeight(.medium)
                        }
                        .accessibilityLabel("Share invite code")
                    }

                    // Role info
                    HStack(spacing: 8) {
                        Text("Role:")
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
                }
            }

            // Create another button
            Button(action: {
                viewModel.resetForNew()
            }) {
                Text("Create Another")
                    .foregroundColor(.blue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 16)
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
}

// MARK: - Preview

#if DEBUG
struct CreateInvitationView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Create Invitation Preview")
    }
}
#endif
