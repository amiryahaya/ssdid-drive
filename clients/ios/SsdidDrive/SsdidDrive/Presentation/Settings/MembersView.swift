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
            ZStack {
                if viewModel.isLoading && viewModel.members.isEmpty {
                    ProgressView("Loading members...")
                } else if viewModel.isEmpty {
                    emptyStateView
                } else {
                    memberListView
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadMembers()
            }
            .onChange(of: viewModel.errorMessage) { newValue in
                showingError = newValue != nil
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: memberToChangeRole) { newValue in
                showingChangeRole = newValue != nil
            }
            .confirmationDialog(
                "Change Role",
                isPresented: $showingChangeRole,
                presenting: memberToChangeRole
            ) { member in
                ForEach(viewModel.assignableRoles, id: \.self) { role in
                    if role != member.role {
                        Button(role.displayName) {
                            viewModel.changeRole(member: member, to: role)
                            memberToChangeRole = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    memberToChangeRole = nil
                }
            } message: { member in
                Text("Select a new role for \(member.name)")
            }
            .onChange(of: memberToRemove) { newValue in
                showingRemoveConfirmation = newValue != nil
            }
            .alert(
                "Remove Member",
                isPresented: $showingRemoveConfirmation,
                presenting: memberToRemove
            ) { member in
                Button("Remove", role: .destructive) {
                    viewModel.removeMember(member)
                    memberToRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    memberToRemove = nil
                }
            } message: { member in
                Text("Are you sure you want to remove \(member.name) from this organization? This action cannot be undone.")
            }
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
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.refresh()
        }
    }
}

// MARK: - Member Row

struct MemberRow: View {

    let member: TenantMember
    let isCurrentUser: Bool
    let canManage: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with initials
            ZStack {
                Circle()
                    .fill(isCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(member.initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isCurrentUser ? .white : .primary)
            }

            // Member info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.body)
                        .foregroundColor(.primary)

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

                HStack(spacing: 6) {
                    Text(member.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Role badge
            VStack(alignment: .trailing, spacing: 4) {
                RoleBadge(role: member.role)

                Text("Joined \(member.joinedAt.shortString)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Disclosure for editable members
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
        .accessibilityHint(isCurrentUser ? "You" : (canManage ? "Tap to change role" : ""))
    }
}

// MARK: - Date Extension for shortString

// Date.shortString is already defined in UIExtensions.swift

// MARK: - Preview

#if DEBUG
struct MembersView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Members Preview")
    }
}
#endif
