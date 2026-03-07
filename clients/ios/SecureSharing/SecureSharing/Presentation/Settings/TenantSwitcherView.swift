import SwiftUI

/// View for switching between tenants (organizations)
struct TenantSwitcherView: View {

    @ObservedObject var viewModel: TenantSwitcherViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading && viewModel.availableTenants.isEmpty {
                    ProgressView("Loading organizations...")
                } else if viewModel.availableTenants.isEmpty {
                    emptyStateView
                } else {
                    tenantListView
                }
            }
            .navigationTitle("Switch Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.error ?? "")
            }
            .onChange(of: viewModel.switchSuccess) { success in
                if success {
                    viewModel.resetSwitchSuccess()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Organizations")
                .font(.headline)

            Text("You're not a member of any organizations yet.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var tenantListView: some View {
        List {
            ForEach(viewModel.availableTenants) { tenant in
                TenantRowView(
                    tenant: tenant,
                    isSelected: tenant.id == viewModel.currentTenant?.id,
                    isSwitching: viewModel.isSwitching && tenant.id != viewModel.currentTenant?.id,
                    onSelect: {
                        viewModel.switchTenant(tenant)
                    }
                )
                .disabled(viewModel.isSwitching)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            viewModel.loadTenants()
        }
    }
}

/// Row view for a single tenant in the list
struct TenantRowView: View {

    let tenant: Tenant
    let isSelected: Bool
    let isSwitching: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Avatar with initials
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Text(tenant.initials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .primary)
                }

                // Tenant info
                VStack(alignment: .leading, spacing: 2) {
                    Text(tenant.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text(tenant.slug)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        RoleBadge(role: tenant.role)
                    }
                }

                Spacer()

                // Selection indicator or loading
                if isSwitching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tenant.name), \(tenant.role.displayName)")
        .accessibilityHint(isSelected ? "Currently selected" : "Double tap to switch")
    }
}

/// Badge showing user's role in a tenant
struct RoleBadge: View {

    let role: UserRole

    var body: some View {
        Text(role.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch role {
        case .admin:
            return Color.purple.opacity(0.2)
        case .member:
            return Color.blue.opacity(0.2)
        case .viewer:
            return Color.gray.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .admin:
            return .purple
        case .member:
            return .blue
        case .viewer:
            return .gray
        }
    }
}

// MARK: - Compact Tenant Indicator

/// Compact indicator showing current tenant (for use in navigation bar or header)
struct TenantIndicatorView: View {

    let tenant: Tenant?
    let tenantCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "building.2")
                    .font(.caption)

                if let tenant = tenant {
                    Text(tenant.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if tenantCount > 1 {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                } else {
                    Text("Select Organization")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(tenantCount <= 1)
    }
}

// MARK: - Settings Card

/// Card view for tenant info in Settings screen
struct TenantSettingsCard: View {

    let tenant: Tenant?
    let tenantCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: "building.2.fill")
                        .foregroundColor(.blue)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    if let tenant = tenant {
                        Text(tenant.name)
                            .font(.body)
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            RoleBadge(role: tenant.role)

                            if tenantCount > 1 {
                                Text("\(tenantCount) organizations")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Organization")
                            .font(.body)
                            .foregroundColor(.primary)

                        Text("Not selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if tenantCount > 1 {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(tenantCount <= 1)
        .accessibilityLabel(tenant?.name ?? "Organization")
    }
}

// MARK: - Preview

#if DEBUG
struct TenantSwitcherView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview would require mock data
        Text("Tenant Switcher Preview")
    }
}
#endif
