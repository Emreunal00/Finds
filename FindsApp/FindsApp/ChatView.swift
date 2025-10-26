import SwiftUI

struct ChatView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Chat yakında!")
                    .font(.title3).bold()
                Text("Bu alan sohbet özelliği için yer tutucudur.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Chat")
        }
    }
}

#Preview {
    ChatView()
}

