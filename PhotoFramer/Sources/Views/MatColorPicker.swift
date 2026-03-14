import SwiftUI

struct MatColorPicker: View {
    @Binding var color: Color

    private let presets: [(String, Color)] = [
        ("White", .white),
        ("Black", .black),
        ("Cream", Color(red: 1.0, green: 0.99, blue: 0.93)),
        ("Gray", .gray),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mat Color")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(presets, id: \.0) { name, preset in
                    Button {
                        color = preset
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(preset)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                .frame(width: 32, height: 32)
                            Text(name)
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 40)

                ColorPicker("Custom", selection: $color, supportsOpacity: false)
                    .labelsHidden()
            }
        }
        .padding(.horizontal)
    }
}
