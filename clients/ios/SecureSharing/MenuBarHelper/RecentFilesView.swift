import SwiftUI

struct RecentFilesView: View {

    let files: [RecentFile]
    let onFileSelected: (RecentFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if files.isEmpty {
                Text("No recent files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                Text("Recent Files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(files.prefix(5)) { file in
                    Button(action: { onFileSelected(file) }) {
                        fileRow(file)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Row

    private func fileRow(_ file: RecentFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.iconName)
                .foregroundColor(.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(file.formattedSize)
                    Text("·")
                    Text(file.updatedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
