import SwiftUI
import Combine

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
    let contentID: String
    let title: String
    let posterURL: URL?
    let type: String

    enum CodingKeys: String, CodingKey {
        case contentID = "content_id"
        case bookID = "book_id"
        case title
        case posterURL = "poster_url"
        case imageURL = "image_url"
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .contentID) {
            contentID = value
        } else if let value = try? container.decode(Int.self, forKey: .contentID) {
            contentID = String(value)
        } else {
            contentID = try container.decode(String.self, forKey: .bookID)
        }
        id = Int(contentID) ?? Self.stableNumericID(for: contentID)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(String.self, forKey: .type)

        let urlString = (try? container.decode(String.self, forKey: .posterURL))
            ?? (try? container.decode(String.self, forKey: .imageURL))
        posterURL = urlString
            .map { $0.replacingOccurrences(of: "http://", with: "https://") }
            .flatMap(URL.init(string:))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contentID, forKey: .contentID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(posterURL?.absoluteString, forKey: .posterURL)
        try container.encode(type, forKey: .type)
    }

    private static func stableNumericID(for string: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(hash & 0x7fffffff)
    }
}

private struct BotEnvelope: Decodable {
    let bot_message: String?
    let recommendations: [BotRecommendation]?
}

@MainActor
final class ChatSessionStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var liveRecommendations: [BotRecommendation] = []

    private var activeConversationID: String?
    private var excludedContentIDs: Set<String> = []
    private var lastRecommendationQuery: String?

    func activate(userID: String?, profileID: String?) {
        let conversationID = [userID, profileID].compactMap { $0 }.joined(separator: ":")
        guard conversationID != activeConversationID else { return }
        activeConversationID = conversationID.isEmpty ? nil : conversationID
        messages = []
        liveRecommendations = []
        excludedContentIDs = []
        lastRecommendationQuery = nil
    }

    func effectiveQuery(for query: String) -> String {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let followUpQueries = ["farklı", "daha", "başka", "daha farklı", "başka öner", "daha öner"]
        if followUpQueries.contains(where: { normalized == $0 || normalized.hasPrefix("\($0) ") }),
           let lastRecommendationQuery {
            return lastRecommendationQuery
        }
        lastRecommendationQuery = query
        return query
    }

    func record(_ recommendations: [BotRecommendation]) {
        liveRecommendations = recommendations
        excludedContentIDs.formUnion(recommendations.map(\.contentID))
    }

    var excludedIDs: [String] {
        excludedContentIDs.sorted()
    }
}

struct ChatView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var chatSession: ChatSessionStore
    @State private var draft: String = ""
    @State private var isSending: Bool = false
    @State private var selectedMood: String? = nil

    private var messages: [ChatMessage] { chatSession.messages }
    private var liveRecs: [BotRecommendation] { chatSession.liveRecommendations }

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
                        
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                
                
                if !liveRecs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(liveRecs) { rec in
                                NavigationLink {
                                    
                                    let mediaType = rec.type.lowercased()
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
                                        externalContentID: mediaType == "book" ? rec.contentID : nil,
                                        cast: nil,
                                        directors: nil,
                                        popularity: nil
                                    )
                                    MediaDetailDestination(item: movie)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack {
                                            Color(.tertiarySystemFill)
                                            if let url = rec.posterURL {
                                                AsyncImage(url: url) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        CustomLoadingView()
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

                
                ScrollView(.horizontal, showsIndicators: false) {
                    let moods: [(value: String, title: String, icon: String)] = [
                        ("happy", "Happy", "face.smiling"),
                        ("sad", "Sad", "face.dashed"),
                        ("excited", "Excited", "sparkles"),
                        ("chill", "Calm", "wind"),
                        ("scared", "Scared", "exclamationmark.triangle"),
                        ("tense", "Tense", "bolt"),
                    ]
                    HStack(spacing: 8) {
                        ForEach(moods, id: \.value) { mood in
                            Button {
                                selectedMood = mood.value
                                Task { await sendMood(mood.value) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mood.icon)
                                    Text(mood.title)
                                }
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedMood == mood.value ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
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
                chatSession.activate(userID: authVM.user?.id, profileID: authVM.currentProfile?.id)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: authVM.user?.id) { _, _ in
                chatSession.activate(userID: authVM.user?.id, profileID: authVM.currentProfile?.id)
                self.selectedMood = nil
            }
            .onChange(of: authVM.currentProfile?.id) { _, _ in
                chatSession.activate(userID: authVM.user?.id, profileID: authVM.currentProfile?.id)
                self.selectedMood = nil
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
                                    colors: [Color.green, Color.green.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: .green.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func chatbotURL(userID: String, profileID: String, query: String? = nil, mood: String? = nil) -> URL? {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "profileId", value: profileID)
        ]
        if let q = query, !q.isEmpty { items.append(URLQueryItem(name: "query", value: q)) }
        if let m = mood, !m.isEmpty { items.append(URLQueryItem(name: "mood", value: m)) }
        if !chatSession.excludedIDs.isEmpty {
            items.append(URLQueryItem(name: "excludeIds", value: chatSession.excludedIDs.joined(separator: ",")))
        }
        return FindsAPI.url(path: "api/v1/chatbot", queryItems: items)
    }

    private func fetchBotResponse(query: String? = nil, mood: String? = nil) async throws -> (message: String, recs: [BotRecommendation]) {
        guard let uid = authVM.user?.id, !uid.isEmpty,
              let profileID = authVM.currentProfile?.id,
              let url = chatbotURL(userID: uid, profileID: profileID, query: query, mood: mood) else {
            throw URLError(.userAuthenticationRequired)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw NSError(domain: "Chatbot", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
        }

        
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("Chatbot raw response:", raw)

        do {
            let env = try JSONDecoder().decode(BotEnvelope.self, from: data)
            let message = env.bot_message ?? ""
            let recs = env.recommendations ?? []
            return (message, recs)
        } catch {
            
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
        let effectiveQuery = chatSession.effectiveQuery(for: trimmed)
        let userMsg = ChatMessage(text: trimmed, isMe: true, date: .now)
        chatSession.messages.append(userMsg)
        draft = ""
        isSending = true

        let typingID = UUID()
        chatSession.messages.append(ChatMessage(id: typingID, text: "…", isMe: false, date: .now))

        Task {
            defer { isSending = false }
            do {
                let result = try await fetchBotResponse(query: effectiveQuery, mood: nil)
                if let idx = chatSession.messages.firstIndex(where: { $0.id == typingID }) {
                    chatSession.messages.remove(at: idx)
                }
                let botMsg = ChatMessage(text: result.message.isEmpty ? "(no reply)" : result.message, isMe: false, date: .now)
                chatSession.messages.append(botMsg)
                chatSession.record(result.recs)
            } catch {
                if let idx = chatSession.messages.firstIndex(where: { $0.id == typingID }) {
                    chatSession.messages.remove(at: idx)
                }
                let errMsg = ChatMessage(text: "Failed: \(error.localizedDescription)", isMe: false, date: .now)
                chatSession.messages.append(errMsg)
                chatSession.liveRecommendations = []
            }
        }
    }

    private func sendMood(_ mood: String) async {
        isSending = true
        let typingID = UUID()
        chatSession.messages.append(ChatMessage(id: typingID, text: "…", isMe: false, date: .now))
        do {
            let result = try await fetchBotResponse(query: "\(mood) ruh halime uygun film öner", mood: mood)
            if let idx = chatSession.messages.firstIndex(where: { $0.id == typingID }) {
                chatSession.messages.remove(at: idx)
            }
            let botMsg = ChatMessage(text: result.message.isEmpty ? "(no reply)" : result.message, isMe: false, date: .now)
            chatSession.messages.append(botMsg)
            chatSession.record(result.recs)
        } catch {
            if let idx = chatSession.messages.firstIndex(where: { $0.id == typingID }) {
                chatSession.messages.remove(at: idx)
            }
            let errMsg = ChatMessage(text: "Failed: \(error.localizedDescription)", isMe: false, date: .now)
            chatSession.messages.append(errMsg)
            chatSession.liveRecommendations = []
        }
        isSending = false
    }
}

#Preview {
    ChatView()
        .environmentObject(AuthViewModel())
        .environmentObject(ChatSessionStore())
}
