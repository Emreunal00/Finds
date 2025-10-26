import SwiftUI

struct PickerView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Picker")
                    .font(.title3).bold()
                Text("This area is a placeholder for the upcoming feature.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Picker")
        }
    }
}

#Preview {
    PickerView()
}

