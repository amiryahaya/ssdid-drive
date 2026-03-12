import SwiftUI

/// SwiftUI view for viewing and managing tenant members (Admin/Owner only)
struct MembersView: View {

    @ObservedObject var viewModel: MembersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var memberToChangeRole: TenantMember?
    @State private var memberToRemove: TenantMember?
    @State private var showingError = false
    @State private var showingChangeRole = false
    @State private var showingRemoveConfirmation = false

    var body: some View {
        NavigationView {
            mainContent
        }
    }

    private var mainContent: some View {
        contentView
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { viewModel.loadMembers() }
            .modifier(MembersAlerts(
                viewModel: viewModel,
                showingError: $showingError,
                showingChangeRole: $showingChangeRole,
                showingRemoveConfirmation: $showingRemoveConfirmation,
                memberToChangeRole: $memberToChangeRole,
                memberToRemove: $memberToRemove
            ))
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && viewModel.members.isEmpty {
            ProgressView("Loading members...")
        } else if viewModel.isEmpty {
            emptyStateView
        } else {
            memberListView
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Members")
                .font(.headline)

            Text("This organization doesn't have any members yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Member List

    private var memberListView: some View {
        List {
            ForEach(viewModel.members) { member in
                memberRow(for: member)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.refresh()
        }
    }

    private func memberRow(for member: TenantMember) -> some View {
        MemberRow(
            member: member,
            isCurrentUser: viewModel.isCurrentUser(member: member),
            canManage: viewModel.canModify(member: member)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.canModify(member: member) {
                memberToChangeRole = member
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if viewModel.canModify(member: member) {
                Button(role: .destructive) {
                    memberToRemove = member
                } label: {
                    Label("Remove", systemImage: "person.badge.minus")
                }
            }
        }
    }
}

// MARK: - Alerts Modifier

private struct MembersAlerts: ViewModifier {
    @ObservedObject var viewModel: MembersViewModel
    @Binding var showingError: Bool
    @Binding var showingChangeRole: Bool
    @Binding var showingRemoveConfirmation: Bool
    @Binding var memberToChangeRole: TenantMember?
    @Binding var memberToRemove: TenantMember?

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.errorMessage) { val in showingError = val != nil }
            .onChange(of: memberToChangeRole) { val in showingChangeRole = val != nil }
            .onChange(of: memberToRemove) { val in showingRemoveConfirmation = val != nil }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .confirmationDialog("Change Role", isPresented: $showingChangeRole, presenting: memberToChangeRole) { member in
                roleButtons(for: member)
            } message: { member in
                Text("Select a new role for \(member.name)")
            }
            .alert("Remove Member", isPresented: $showingRemoveConfirmation, presenting: memberToRemove) { member in
                Button("Remove", role: .destructive) {
                    viewModel.removeMember(member)
                    memberToRemove = nil
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: { member in
                Text("Remove \(member.name) from this organization?")
            }
    }

    @ViewBuilder
    private func roleButtons(for member: TenantMember) -> some View {
        let roles = viewModel.assignableRoles.filter { $0 != member.role }
        ForEach(roles, id: \.self) { role in
            Button(role.displayName) {
                viewModel.changeRole(member: member, to: role)
                memberToChangeRole = nil
            }
        }
        Button("Cancel", role: .cancel) { memberToChangeRole = nil }
    }
}

// MARK: - Member Row

struct MemberRow: View {

    let member: TenantMember
    let isCurrentUser: Bool
    let canManage: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatarView
            infoView
            Spacer()
            roleView
            if canManage {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isCurrentUser ? Color.blue.opacity(0.05) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(member.name), \(member.role.displayName)")
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(isCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                .frame(width: 44, height: 44)
            Text(member.initials)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isCurrentUser ? .white : .primary)
        }
    }

    private var infoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(member.name)
                    .font(.body)
                if isCurrentUser {
                    Text("You")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
            Text(member.email)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var roleView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            RoleBadge(role: member.role)
            Text("Joined \(member.joinedAt.shortString)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MembersView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Members Preview")
    }
}
#endif
