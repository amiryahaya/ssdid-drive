import SwiftUI

/// SwiftUI view for listing received and sent tenant invitations
struct InvitationsListView: View {

    @ObservedObject var viewModel: InvitationsListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $viewModel.selectedTab) {
                    ForEach(InvitationsListViewModel.Tab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Content
                switch viewModel.selectedTab {
                case .received:
                    receivedListView
                case .sent:
                    sentListView
                }
            }
            .navigationTitle("Invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadAll()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Received Tab

    private var receivedListView: some View {
        Group {
            if viewModel.isLoading && viewModel.receivedInvitations.isEmpty {
                ProgressView("Loading invitations...")
                    .frame(maxHeight: .infinity)
            } else if viewModel.isReceivedEmpty {
                emptyView(
                    icon: "envelope.open",
                    title: "No Invitations",
                    subtitle: "You don't have any pending invitations."
                )
            } else {
                List {
                    ForEach(viewModel.receivedInvitations) { invitation in
                        ReceivedInvitationRow(
                            invitation: invitation,
                            onAccept: { viewModel.acceptInvitation(invitation) },
                            onDecline: { viewModel.declineInvitation(invitation) }
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    viewModel.refresh()
                }
            }
        }
    }

    // MARK: - Sent Tab

    private var sentListView: some View {
        Group {
            if viewModel.isLoading && viewModel.sentInvitations.isEmpty {
                ProgressView("Loading invitations...")
                    .frame(maxHeight: .infinity)
            } else if viewModel.isSentEmpty {
                emptyView(
                    icon: "paperplane",
                    title: "No Sent Invitations",
                    subtitle: "You haven't sent any invitations yet."
                )
            } else {
                List {
                    ForEach(viewModel.sentInvitations) { invitation in
                        SentInvitationRow(invitation: invitation)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if invitation.status == .pending {
                                    Button(role: .destructive) {
                                        viewModel.revokeInvitation(invitation)
                                    } label: {
                                        Label("Revoke", systemImage: "xmark.circle")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    viewModel.refresh()
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Received Invitation Row

struct ReceivedInvitationRow: View {

    let invitation: TenantInvitation
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tenant name and role
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(invitation.tenantName)
                        .font(.body)
                        .fontWeight(.medium)

                    if let invitedBy = invitation.invitedBy {
                        Text("Invited by \(invitedBy.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                RoleBadge(role: invitation.role)
            }

            // Expiry
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Expires \(invitation.expiresAt.relativeString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Accept/Decline buttons
            HStack(spacing: 12) {
                Button(action: onAccept) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Accept")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept invitation from \(invitation.tenantName)")

                Button(action: onDecline) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Decline")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline invitation from \(invitation.tenantName)")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sent Invitation Row

struct SentInvitationRow: View {

    let invitation: SentInvitation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Email/Open invite and status
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.displayEmail)
                        .font(.body)

                    HStack(spacing: 6) {
                        RoleBadge(role: invitation.role)

                        InvitationStatusBadge(status: invitation.status)
                    }
                }

                Spacer()

                // Short code
                Text(invitation.shortCode)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
            }

            // Date
            Text("Created \(invitation.createdAt.relativeString)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(invitation.displayEmail), \(invitation.role.displayName), \(invitation.status.displayName)")
    }
}

// MARK: - Invitation Status Badge

struct InvitationStatusBadge: View {

    let status: InvitationStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch status {
        case .pending:
            return Color.orange.opacity(0.2)
        case .accepted:
            return Color.green.opacity(0.2)
        case .declined:
            return Color.red.opacity(0.2)
        case .revoked:
            return Color.gray.opacity(0.2)
        case .expired:
            return Color.gray.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .declined:
            return .red
        case .revoked:
            return .gray
        case .expired:
            return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
struct InvitationsListView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Invitations List Preview")
    }
}
#endif
