import SwiftUI

/// SwiftUI view for requesting creation of a new tenant/organization.
/// Presented as a modal with a form for organization name and optional reason.
struct TenantRequestView: View {

    @ObservedObject var viewModel: TenantRequestViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerView

                    switch viewModel.state {
                    case .idle, .loading, .error:
                        formView
                    case .submitted:
                        successView
                    }

                    if let error = viewModel.errorMessage {
                        errorView(message: error)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Create Your Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(viewModel.state == .submitted ? "Done" : "Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Create Your Organization")
                .font(.title2)
                .fontWeight(.bold)

            Text("Submit a request to create a new organization. An administrator will review your request.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Form

    private var formView: some View {
        VStack(spacing: 16) {
            // Organization Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Organization Name")
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("e.g. Acme Corporation", text: $viewModel.organizationName)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .accessibilityLabel("Organization name")
                    .accessibilityHint("Enter the name of your organization")
            }

            // Reason (optional)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reason (optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(viewModel.reasonRemainingCharacters)")
                        .font(.caption)
                        .foregroundColor(
                            viewModel.reasonRemainingCharacters < 50 ? .orange : .secondary
                        )
                }

                TextEditor(text: $viewModel.reason)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .accessibilityLabel("Reason for request")
                    .accessibilityHint("Optionally describe why you need an organization")
                    .onChange(of: viewModel.reason) { newValue in
                        if newValue.count > TenantRequestViewModel.maxReasonLength {
                            viewModel.reason = String(
                                newValue.prefix(TenantRequestViewModel.maxReasonLength))
                        }
                    }
            }

            // Submit Button
            Button(action: {
                viewModel.submitRequest()
            }) {
                HStack {
                    if viewModel.state == .loading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text("Submit Request")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canSubmit ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
                .fontWeight(.semibold)
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityLabel("Submit organization request")
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Request Submitted!")
                .font(.title2)
                .fontWeight(.bold)

            Text(
                "Your request to create an organization has been submitted. You will be notified once it is reviewed."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            Button(action: {
                dismiss()
            }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .fontWeight(.semibold)
            }
            .padding(.top, 8)
            .accessibilityLabel("Done")
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
}

// MARK: - Preview

#if DEBUG
struct TenantRequestView_Previews: PreviewProvider {
    static var previews: some View {
        Text("Tenant Request Preview")
    }
}
#endif
