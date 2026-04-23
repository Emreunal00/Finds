import SwiftUI

private enum QuizTheme {
    static let primary = Color(red: 0.16, green: 0.66, blue: 0.44)
    static let secondary = Color(red: 0.29, green: 0.78, blue: 0.55)
    static let accent = Color(red: 0.77, green: 0.95, blue: 0.84)

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.14, blue: 0.12)
            : Color(red: 0.95, green: 0.98, blue: 0.96)
    }

    static func elevatedSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.19, blue: 0.16)
            : Color.white
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color(red: 0.78, green: 0.89, blue: 0.82)
    }

    static func overlay(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.04)
    }
}

struct HomeMiniGameLauncher: View {
    @Binding var isPresented: Bool

    @State private var dragOffset = CGSize.zero
    @State private var containerSize = CGSize.zero
    @State private var settledOffset = CGSize(width: 0, height: 250)
    @State private var hasInitializedPosition = false
    @State private var didDragLauncher = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isPresented {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    MovieQuoteQuizPopup(isPresented: $isPresented)
                        .frame(
                            maxWidth: min(geometry.size.width - 24, 390),
                            maxHeight: min(geometry.size.height - 48, 620)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 24)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }

                launcher
                    .position(
                        x: clampedX(in: geometry.size),
                        y: clampedY(in: geometry.size)
                    )
                    .zIndex(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: isPresented)
            .onAppear {
                containerSize = geometry.size
                guard !hasInitializedPosition else { return }
                hasInitializedPosition = true
                settledOffset = defaultOffset(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newValue in
                containerSize = newValue
                if !hasInitializedPosition {
                    settledOffset = defaultOffset(in: newValue)
                    hasInitializedPosition = true
                } else {
                    settledOffset.width = settledOffset.width < newValue.width / 2 ? 60 : max(newValue.width - 60, 60)
                    settledOffset.height = min(max(settledOffset.height, 120), max(newValue.height - 110, 120))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var launcher: some View {
        launcherArtwork
            .frame(width: 108, height: 108)
            .contentShape(Rectangle())
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 6)
            .gesture(
                DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let translation = value.translation
                    let dragThreshold: CGFloat = 8
                    let distance = hypot(translation.width, translation.height)

                    if distance > dragThreshold {
                        didDragLauncher = true
                        dragOffset = translation
                    }
                }
                .onEnded { value in
                    let translation = value.translation
                    let dragThreshold: CGFloat = 8
                    let distance = hypot(translation.width, translation.height)

                    if distance > dragThreshold {
                        settledOffset.width += translation.width
                        settledOffset.height += translation.height
                        snapToNearestEdge(in: containerSize)
                    } else if !didDragLauncher {
                        isPresented = true
                    }

                    dragOffset = .zero
                    didDragLauncher = false
                }
            )
            .accessibilityLabel("Movie quote quiz")
    }

    @ViewBuilder
    private var launcherArtwork: some View {
        if UIImage(named: "QuizgameLogo") != nil {
            Image("QuizgameLogo")
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(QuizTheme.primary)
        }
    }

    private func clampedX(in size: CGSize) -> CGFloat {
        let halfWidth: CGFloat = 54
        let rawX = settledOffset.width + dragOffset.width
        return min(max(rawX, halfWidth), max(size.width - halfWidth, halfWidth))
    }

    private func clampedY(in size: CGSize) -> CGFloat {
        let rawY = settledOffset.height + dragOffset.height
        return min(max(rawY, 64), max(size.height - 110, 64))
    }

    private func defaultOffset(in size: CGSize) -> CGSize {
        CGSize(width: max(size.width - 54, 54), height: min(max(size.height * 0.28, 96), size.height - 140))
    }

    private func snapToNearestEdge(in size: CGSize) {
        guard size != .zero else { return }
        let leftEdgeX: CGFloat = 54
        let rightEdgeX = max(size.width - 54, leftEdgeX)
        let topEdgeY: CGFloat = 64
        let bottomLimit = max(size.height - 110, topEdgeY)

        let clampedX = min(max(settledOffset.width, leftEdgeX), rightEdgeX)
        let clampedY = min(max(settledOffset.height, topEdgeY), bottomLimit)

        let distanceToLeft = abs(clampedX - leftEdgeX)
        let distanceToRight = abs(rightEdgeX - clampedX)
        let distanceToTop = abs(clampedY - topEdgeY)

        if distanceToTop <= distanceToLeft && distanceToTop <= distanceToRight {
            settledOffset.width = clampedX
            settledOffset.height = topEdgeY
        } else if distanceToLeft <= distanceToRight {
            settledOffset.width = leftEdgeX
            settledOffset.height = clampedY
        } else {
            settledOffset.width = rightEdgeX
            settledOffset.height = clampedY
        }
    }
}

private struct MovieQuoteQuizPopup: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme

    @State private var questions: [MovieQuoteQuestion] = MovieQuoteQuestion.loadQuizData()
    @State private var currentIndex = 0
    @State private var score = 0
    @State private var selectedOption: String?
    @State private var showSummary = false

    private var currentQuestion: MovieQuoteQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            launcherBadge
                            Text("Movie Quote Quiz")
                                .font(.title3.bold())
                        }
                        Text("Guess the film from the line.")
                            .font(.headline)
                            .foregroundStyle(QuizTheme.primary)
                        Text("Alintiyi okuyup dogru filmi isaretle.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(QuizTheme.primary)
                            .frame(width: 28, height: 28)
                            .background(QuizTheme.overlay(for: colorScheme), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close movie quote quiz")
                }

                HStack(spacing: 12) {
                    statCard(title: "Score", value: "\(score)")
                    statCard(title: "Question", value: "\(min(currentIndex + 1, questions.count))/\(questions.count)")
                }

                if showSummary {
                    summaryView
                } else if let question = currentQuestion {
                    questionView(question)
                } else {
                    Text("Question could not be loaded.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [QuizTheme.elevatedSurface(for: colorScheme), QuizTheme.surface(for: colorScheme)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(QuizTheme.border(for: colorScheme), lineWidth: 1)
        }
        .shadow(color: QuizTheme.primary.opacity(0.14), radius: 24, y: 14)
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quiz tamamlandi")
                .font(.headline)

            Text("Toplam \(score) dogru cevap verdin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Restart quiz") {
                restartQuiz()
            }
            .buttonStyle(.borderedProminent)
            .tint(QuizTheme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(QuizTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func questionView(_ question: MovieQuoteQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuizTheme.primary)

                Text("“\(question.quote)”")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                LinearGradient(
                    colors: [QuizTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.55), QuizTheme.surface(for: colorScheme)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )

            VStack(spacing: 10) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        select(option, for: question)
                    } label: {
                        HStack {
                            Text(option)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if selectedOption != nil {
                                Image(systemName: iconName(for: option, answer: question.answer))
                                    .foregroundStyle(iconColor(for: option, answer: question.answer))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(backgroundColor(for: option, answer: question.answer), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedOption != nil)
                }
            }

            if selectedOption != nil {
                Text(selectedOption == question.answer ? "Dogru cevap." : "Dogru cevap: \(question.answer)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedOption == question.answer ? QuizTheme.primary : .secondary)

                Button(currentIndex == questions.count - 1 ? "Finish" : "Next question") {
                    advanceQuiz()
                }
                .buttonStyle(.borderedProminent)
                .tint(QuizTheme.primary)
            }
        }
    }

    private func select(_ option: String, for question: MovieQuoteQuestion) {
        guard selectedOption == nil else { return }
        selectedOption = option
        if option == question.answer {
            score += 1
        }
    }

    private func advanceQuiz() {
        selectedOption = nil
        if currentIndex == questions.count - 1 {
            showSummary = true
        } else {
            currentIndex += 1
        }
    }

    private func restartQuiz() {
        questions = MovieQuoteQuestion.loadQuizData()
        currentIndex = 0
        score = 0
        selectedOption = nil
        showSummary = false
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(QuizTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func backgroundColor(for option: String, answer: String) -> Color {
        guard let selectedOption else { return QuizTheme.elevatedSurface(for: colorScheme) }
        if option == answer {
            return QuizTheme.secondary.opacity(0.22)
        }
        if option == selectedOption {
            return Color.red.opacity(0.12)
        }
        return QuizTheme.surface(for: colorScheme)
    }

    private func iconName(for option: String, answer: String) -> String {
        guard let selectedOption else { return "circle" }
        if option == answer {
            return "checkmark.circle.fill"
        }
        if option == selectedOption {
            return "xmark.circle.fill"
        }
        return "circle"
    }

    private func iconColor(for option: String, answer: String) -> Color {
        guard let selectedOption else { return .secondary }
        if option == answer {
            return QuizTheme.primary
        }
        if option == selectedOption {
            return .red
        }
        return .secondary
    }

    @ViewBuilder
    private var launcherBadge: some View {
        if UIImage(named: "QuizgameLogo") != nil {
            Image("QuizgameLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct MovieQuoteQuestion: Codable, Identifiable {
    let quote: String
    let answer: String
    let options: [String]

    var id: String { quote }

    static func loadQuizData() -> [MovieQuoteQuestion] {
        if let csvQuestions = loadQuestionsFromCSV(), !csvQuestions.isEmpty {
            return csvQuestions.shuffled()
        }

        if let url = Bundle.main.url(forResource: "movie_quotes_quiz", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([MovieQuoteQuestion].self, from: data),
           !decoded.isEmpty {
            return decoded.shuffled()
        }

        return sampleQuestions.shuffled()
    }

    private static func loadQuestionsFromCSV() -> [MovieQuoteQuestion]? {
        guard let url = Bundle.main.url(forResource: "movie_quotes", withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let rows = parseCSVRows(from: content)
        guard let header = rows.first, rows.count > 1 else { return nil }

        let normalizedHeader = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let quoteIndex = index(in: normalizedHeader, matchingAny: ["quote", "quotes", "line", "text"]),
              let movieIndex = index(in: normalizedHeader, matchingAny: ["movie", "title", "film"]) else {
            return nil
        }
        let typeIndex = index(in: normalizedHeader, matchingAny: ["type"])

        var groupedQuotes: [String: [String]] = [:]
        for row in rows.dropFirst() {
            guard row.indices.contains(quoteIndex), row.indices.contains(movieIndex) else { continue }

            let quote = row[quoteIndex].cleanedCSVField
            let movie = row[movieIndex].cleanedCSVField
            let contentType = typeIndex.flatMap { row.indices.contains($0) ? row[$0].cleanedCSVField.lowercased() : nil }

            guard !quote.isEmpty, !movie.isEmpty else { continue }
            if let contentType, contentType != "movie" { continue }
            groupedQuotes[movie, default: []].append(quote)
        }

        let movieTitles = Array(groupedQuotes.keys)
        guard movieTitles.count >= 4 else { return nil }

        var generator = SystemRandomNumberGenerator()
        let questions: [MovieQuoteQuestion] = groupedQuotes.compactMap { movie, quotes in
            guard let quote = quotes.randomElement(using: &generator) else { return nil }
            let distractors = movieTitles
                .filter { $0 != movie }
                .shuffled(using: &generator)
                .prefix(3)

            guard distractors.count == 3 else { return nil }

            let options = ([movie] + distractors).shuffled(using: &generator)
            return MovieQuoteQuestion(quote: quote, answer: movie, options: options)
        }

        return Array(questions.shuffled(using: &generator).prefix(12))
    }

    private static func parseCSVRows(from content: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false

        for character in content {
            switch character {
            case "\"":
                if isInsideQuotes && field.last == "\"" {
                    field.removeLast()
                    field.append("\"")
                } else {
                    isInsideQuotes.toggle()
                    field.append("\"")
                }
            case ",":
                if isInsideQuotes {
                    field.append(character)
                } else {
                    row.append(field)
                    field = ""
                }
            case "\n":
                if isInsideQuotes {
                    field.append(character)
                } else {
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                }
            case "\r":
                continue
            default:
                field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    private static func index(in header: [String], matchingAny candidates: [String]) -> Int? {
        header.firstIndex { key in
            candidates.contains(where: { key.contains($0) })
        }
    }

    private static let sampleQuestions: [MovieQuoteQuestion] = [
        MovieQuoteQuestion(
            quote: "May the Force be with you.",
            answer: "Star Wars",
            options: ["Star Wars", "Dune", "Avatar", "The Matrix"]
        ),
        MovieQuoteQuestion(
            quote: "I'm going to make him an offer he can't refuse.",
            answer: "The Godfather",
            options: ["Goodfellas", "Scarface", "The Godfather", "Casino"]
        ),
        MovieQuoteQuestion(
            quote: "Here's looking at you, kid.",
            answer: "Casablanca",
            options: ["Casablanca", "Citizen Kane", "Psycho", "Vertigo"]
        ),
        MovieQuoteQuestion(
            quote: "You talking to me?",
            answer: "Taxi Driver",
            options: ["The Departed", "Taxi Driver", "Joker", "Heat"]
        ),
        MovieQuoteQuestion(
            quote: "Why so serious?",
            answer: "The Dark Knight",
            options: ["Batman Begins", "The Dark Knight", "Joker", "Se7en"]
        ),
        MovieQuoteQuestion(
            quote: "I see dead people.",
            answer: "The Sixth Sense",
            options: ["The Others", "Insidious", "The Sixth Sense", "The Ring"]
        ),
        MovieQuoteQuestion(
            quote: "Life is like a box of chocolates.",
            answer: "Forrest Gump",
            options: ["Big Fish", "Forrest Gump", "The Green Mile", "Cast Away"]
        ),
        MovieQuoteQuestion(
            quote: "I'll be back.",
            answer: "The Terminator",
            options: ["RoboCop", "Predator", "The Terminator", "Total Recall"]
        )
    ]
}

private extension String {
    var cleanedCSVField: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.08).ignoresSafeArea()
        HomeMiniGameLauncher(isPresented: .constant(true))
    }
}
