import SwiftUI

struct FrameSizePicker: View {
    @Binding var selection: FrameSize

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(FrameSizeCategory.allCases) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FrameSize.sizes(for: category)) { size in
                            FrameSizeCell(
                                size: size,
                                isSelected: selection == size
                            )
                            .onTapGesture { selection = size }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct FrameSizeCell: View {
    let size: FrameSize
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Aspect ratio preview rectangle
            let ar = size.aspectRatio
            let previewWidth: CGFloat = 40
            let previewHeight: CGFloat = 40

            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
                .frame(
                    width: ar >= 1 ? previewWidth : previewHeight * ar,
                    height: ar >= 1 ? previewWidth / ar : previewHeight
                )

            Text(size.label)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
    }
}
