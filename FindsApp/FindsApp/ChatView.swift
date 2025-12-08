import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let isMe: Bool
    let date: Date
    init(id: UUID = UUID(), text: String, isMe: Bool, date: Date) {
        self.id = id
        self.text = text
        self.isMe = isMe
        self.date = date
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isMe { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isMe ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(message.isMe ? Color.accentColor : Color(.secondarySystemBackground))
                    )
                Text(message.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            if !message.isMe { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }
}

struct ChatView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var selectedMood: String? = nil // optional mood quick filter

    private let baseURL = URL(string: "https://finds-api-91195881425.europe-west3.run.app")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "ellipsis.bubble")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("No messages yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages) { _, _ in
                        // Auto scroll to bottom when new message arrives
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                
                // Quick mood buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["happy","sad","excited","chill","scared","tense"], id: \.self) { mood in
                            Button {
                                selectedMood = mood
                                Task { await sendMood(mood) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "face.smiling")
                                    Text(mood.capitalized)
                                }
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedMood == mood ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }

                inputBar
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .padding(.bottom, 6)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack {
                TextField("Type here...", text: $draft)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)

            Button(action: { send() }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: .purple.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func chatbotURL(userID: String, query: String? = nil, mood: String? = nil) -> URL? {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/chatbot"), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [URLQueryItem(name: "userId", value: userID)]
        if let q = query, !q.isEmpty { items.append(URLQueryItem(name: "query", value: q)) }
        if let m = mood, !m.isEmpty { items.append(URLQueryItem(name: "mood", value: m)) }
        comps?.queryItems = items
        return comps?.url
    }

    private func fetchBotResponse(query: String? = nil, mood: String? = nil) async throws -> String {
        guard let uid = authVM.user?.id, !uid.isEmpty, let url = chatbotURL(userID: uid, query: query, mood: mood) else {
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw NSError(domain: "Chatbot", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }
        struct Envelope: Decodable { let bot_message: String? }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return env.bot_message ?? ""
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMsg = ChatMessage(text: trimmed, isMe: true, date: .now)
        messages.append(userMsg)
        draft = ""
        isSending = true

        // Optional: show typing indicator
        let typingID = UUID()
        let typing = ChatMessage(id: typingID, text: "…", isMe: false, date: .now)
        messages.append(typing)

        Task {
            defer { isSending = false }
            do {
                let reply = try await fetchBotResponse(query: userMsg.text, mood: nil)
                // replace typing with actual reply
                if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
                messages.append(ChatMessage(text: reply.isEmpty ? "(no reply)" : reply, isMe: false, date: .now))
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
                messages.append(ChatMessage(text: "Failed: \(error.localizedDescription)", isMe: false, date: .now))
            }
        }
    }

    private func sendMood(_ mood: String) async {
        isSending = true
        let typingID = UUID()
        let typing = ChatMessage(id: typingID, text: "…", isMe: false, date: .now)
        messages.append(typing)
        do {
            let reply = try await fetchBotResponse(query: nil, mood: mood)
            if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
            messages.append(ChatMessage(text: reply.isEmpty ? "(no reply)" : reply, isMe: false, date: .now))
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
            messages.append(ChatMessage(text: "Failed: \(error.localizedDescription)", isMe: false, date: .now))
        }
        isSending = false
    }
}

#Preview {
    ChatView()
}
