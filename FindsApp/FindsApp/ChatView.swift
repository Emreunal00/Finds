import SwiftUI
import FirebaseFirestore

struct ChatMessage: Identifiable, Equatable, Codable {
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

struct BotRecommendation: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let posterURL: URL?
    let type: String // "movie" or "tv"

    enum CodingKeys: String, CodingKey {
        case content_id
        case title
        case poster_url
        case type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let contentID = try c.decode(String.self, forKey: .content_id)
        self.id = Int(contentID) ?? contentID.hashValue
        self.title = try c.decode(String.self, forKey: .title)
        if let urlStr = try? c.decode(String.self, forKey: .poster_url) {
            self.posterURL = URL(string: urlStr)
        } else {
            self.posterURL = nil
        }
        self.type = try c.decode(String.self, forKey: .type)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Encode id back as string for content_id to match decoding
        try container.encode(String(id), forKey: .content_id)
        try container.encode(title, forKey: .title)
        if let url = posterURL {
            try container.encode(url.absoluteString, forKey: .poster_url)
        } else {
            try container.encodeNil(forKey: .poster_url)
        }
        try container.encode(type, forKey: .type)
    }
}

private struct BotEnvelope: Decodable {
    let bot_message: String?
    let recommendations: [BotRecommendation]?
}

struct ChatView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var selectedMood: String? = nil // optional mood quick filter
    @State private var liveRecs: [BotRecommendation] = []
    @SceneStorage("chat.messages") private var storedMessagesData: Data?
    @SceneStorage("chat.liveRecs") private var storedLiveRecsData: Data?

    private let baseURL = URL(string: "https://finds-api-91195881425.europe-west3.run.app")!

    private let db = Firestore.firestore()

    private func messagesCollection(for userID: String) -> CollectionReference {
        db.collection("users").document(userID).collection("chat_history")
    }

    private func saveMessage(_ message: ChatMessage, for userID: String) {
        // Do not persist typing placeholders
        if message.text == "…" { return }
        let doc = messagesCollection(for: userID).document(message.id.uuidString)
        let data: [String: Any] = [
            "id": message.id.uuidString,
            "text": message.text,
            "isMe": message.isMe,
            // Store as Firestore timestamp
            "date": Timestamp(date: message.date)
        ]
        doc.setData(data, merge: true) { error in
            if let error = error {
                print("Failed to save message: \(error.localizedDescription)")
            }
        }
    }

    private func startListeningHistory(for userID: String) {
        messagesCollection(for: userID)
            .order(by: "date", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("History listen error: \(error.localizedDescription)")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                let decoded: [ChatMessage] = docs.compactMap { doc in
                    let data = doc.data()
                    guard let text = data["text"] as? String,
                          let isMe = data["isMe"] as? Bool,
                          let ts = data["date"] as? Timestamp else { return nil }
                    let idStr = data["id"] as? String
                    let id = idStr.flatMap(UUID.init(uuidString:)) ?? UUID()
                    return ChatMessage(id: id, text: text, isMe: isMe, date: ts.dateValue())
                }
                // Replace local state with remote snapshot to keep in sync
                self.messages = decoded
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "ellipsis.bubble")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Start Chatting")
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
                
                // Live recommendations (poster + title)
                if !liveRecs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(liveRecs) { rec in
                                NavigationLink {
                                    // Construct a lightweight Movie for detail view
                                    let mediaType = rec.type.lowercased() == "tv" ? "tv" : "movie"
                                    let movie = Movie(
                                        id: rec.id,
                                        title: rec.title,
                                        year: 0,
                                        genres: [],
                                        posterName: "",
                                        rating: 0.0,
                                        summary: "",
                                        posterURL: rec.posterURL,
                                        durationMinutes: nil,
                                        mediaType: mediaType,
                                        cast: nil,
                                        directors: nil,
                                        popularity: nil
                                    )
                                    MovieDetailView(movie: movie)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack {
                                            Color(.tertiarySystemFill)
                                            if let url = rec.posterURL {
                                                AsyncImage(url: url) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        ProgressView()
                                                    case .success(let img):
                                                        img.resizable().scaledToFill()
                                                    case .failure:
                                                        Image(systemName: "film")
                                                            .font(.system(size: 20))
                                                            .foregroundStyle(.secondary)
                                                    @unknown default:
                                                        Image(systemName: "film")
                                                            .font(.system(size: 20))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                            } else {
                                                Image(systemName: "film")
                                                    .font(.system(size: 20))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(width: 100, height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                        Text(rec.title)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .frame(width: 100, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
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
            .task {
                // Load messages from SceneStorage to persist during app session
                if let data = storedMessagesData {
                    if let loaded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
                        self.messages = loaded
                    } else {
                        self.messages = []
                    }
                } else {
                    self.messages = []
                }
                if let recsData = storedLiveRecsData, let loadedRecs = try? JSONDecoder().decode([BotRecommendation].self, from: recsData) {
                    self.liveRecs = loadedRecs
                } else {
                    self.liveRecs = []
                }
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: messages) { _, newValue in
                if let data = try? JSONEncoder().encode(newValue) {
                    self.storedMessagesData = data
                }
            }
            .onChange(of: liveRecs) { _, newValue in
                if let data = try? JSONEncoder().encode(newValue) {
                    self.storedLiveRecsData = data
                }
            }
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

    private func fetchBotResponse(query: String? = nil, mood: String? = nil) async throws -> (message: String, recs: [BotRecommendation]) {
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

        // Debug: log raw body for troubleshooting
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("Chatbot raw response:", raw)

        do {
            let env = try JSONDecoder().decode(BotEnvelope.self, from: data)
            let message = env.bot_message ?? ""
            let recs = env.recommendations ?? []
            return (message, recs)
        } catch {
            // Fallback: treat entire body as plain text message
            if let message = String(data: data, encoding: .utf8) {
                return (message, [])
            } else {
                throw error
            }
        }
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let userMsg = ChatMessage(text: trimmed, isMe: true, date: .now)
        messages.append(userMsg)
        if let uid = authVM.user?.id, !uid.isEmpty {
            saveMessage(userMsg, for: uid)
        }
        draft = ""
        isSending = true

        // Optional: show typing indicator
        let typingID = UUID()
        let typing = ChatMessage(id: typingID, text: "…", isMe: false, date: .now)
        messages.append(typing)

        Task {
            defer { isSending = false }
            do {
                let result = try await fetchBotResponse(query: userMsg.text, mood: nil)
                // replace typing with actual reply
                if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
                let botMsg = ChatMessage(text: result.message.isEmpty ? "(no reply)" : result.message, isMe: false, date: .now)
                messages.append(botMsg)
                self.liveRecs = result.recs
                if let uid = authVM.user?.id, !uid.isEmpty { saveMessage(botMsg, for: uid) }
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
                let errMsg = ChatMessage(text: "Failed: \(error.localizedDescription)", isMe: false, date: .now)
                messages.append(errMsg)
                self.liveRecs = []
                if let uid = authVM.user?.id, !uid.isEmpty { saveMessage(errMsg, for: uid) }
            }
        }
    }

    private func sendMood(_ mood: String) async {
        isSending = true
        let typingID = UUID()
        let typing = ChatMessage(id: typingID, text: "…", isMe: false, date: .now)
        messages.append(typing)
        do {
            let result = try await fetchBotResponse(query: nil, mood: mood)
            if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
            let botMsg = ChatMessage(text: result.message.isEmpty ? "(no reply)" : result.message, isMe: false, date: .now)
            messages.append(botMsg)
            self.liveRecs = result.recs
            if let uid = authVM.user?.id, !uid.isEmpty { saveMessage(botMsg, for: uid) }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == typingID }) { messages.remove(at: idx) }
            let errMsg = ChatMessage(text: "Failed: \(error.localizedDescription)", isMe: false, date: .now)
            messages.append(errMsg)
            self.liveRecs = []
            if let uid = authVM.user?.id, !uid.isEmpty { saveMessage(errMsg, for: uid) }
        }
        isSending = false
    }
}

#Preview {
    ChatView()
}
