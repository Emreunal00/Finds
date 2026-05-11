import SwiftUI
import Combine
import FirebaseFirestore

struct Hello: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var items: [Movie] = []
    @State private var selectedKeys: Set<String> = []
    @State private var isSaving = false
    
    private func key(for movie: Movie) -> String {
        let type = (movie.mediaType ?? "movie").lowercased()
        return "\(type):\(movie.id)"
    }
    
    private func displayTitle(for movie: Movie) -> String {
        return movie.title
    }
    
    private func persistSelection(for movie: Movie, isSelected: Bool) {
        guard let uid = authVM.user?.id else {
            error = "User not authenticated."
            return
        }
        let db = Firestore.firestore()
        let k = key(for: movie)
        let docRef = db.collection("users").document(uid)
            .collection("onboardingSelections").document(k)

        if isSelected {
            
            var data: [String: Any] = [
                "movieId": movie.id,
                "type": (movie.mediaType ?? "movie").lowercased(),
                "title": movie.title,
                "selectedAt": FieldValue.serverTimestamp()
            ]
            if let poster = movie.posterURL?.absoluteString {
                data["posterURL"] = poster
            }
            isSaving = true
            docRef.setData(data, merge: true) { err in
                isSaving = false
                if let err = err {
                    error = "Failed to save selection: \(err.localizedDescription)"
                }
            }
        } else {
            
            isSaving = true
            docRef.delete { err in
                isSaving = false
                if let err = err {
                    error = "Failed to remove selection: \(err.localizedDescription)"
                }
            }
        }
    }
    
    private func load() async {
        do {
            isLoading = true
            error = nil
            async let moviesPage1: [Movie] = MovieService().getTrending(page: 1)
            async let moviesPage2: [Movie] = MovieService().getTrending(page: 2)
            async let moviesPage3: [Movie] = MovieService().getTrending(page: 3)
            async let tvPage1: [Movie] = MovieService().getTrendingTV(page: 1)
            async let tvPage2: [Movie] = MovieService().getTrendingTV(page: 2)
            async let tvPage3: [Movie] = MovieService().getTrendingTV(page: 3)

            let movieResults = try await moviesPage1 + moviesPage2
            let tvResults = try await tvPage1 + tvPage2

            var combined = movieResults + tvResults
            combined.shuffle()

            items = combined
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    private func saveSelections() {
        guard let uid = authVM.user?.id else {
            error = "User not authenticated."
            return
        }
        isSaving = true
        error = nil
        
        let db = Firestore.firestore()
        let batch = db.batch()
        
        for movie in items where selectedKeys.contains(key(for: movie)) {
            let k = key(for: movie)
            let docRef = db.collection("users").document(uid)
                .collection("onboardingSelections").document(k)
            var data: [String: Any] = [
                "movieId": movie.id,
                "type": (movie.mediaType ?? "movie").lowercased(),
                "selectedAt": FieldValue.serverTimestamp()
            ]
            batch.setData(data, forDocument: docRef)
        }
        
        let userDoc = db.collection("users").document(uid)
        batch.setData(["onboardingCompleted": true], forDocument: userDoc, merge: true)
        
        batch.commit { err in
            isSaving = false
            if let err = err {
                error = "Failed to save selections: \(err.localizedDescription)"
            } else {
                dismiss()
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    CustomLoadingView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(items) { movie in
                                let k = key(for: movie)
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: movie.posterURL) { phase in
                                        switch phase {
                                        case .empty:
                                            Color.gray.opacity(0.3)
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        case .failure:
                                            Color.red.opacity(0.3)
                                        @unknown default:
                                            Color.gray.opacity(0.3)
                                        }
                                    }
                                    .frame(height: 220)
                                    .clipped()
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedKeys.contains(k) ? Color.green : Color.clear, lineWidth: 3)
                                    )
                                    
                                    if selectedKeys.contains(k) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.green)
                                            .padding(6)
                                    }
                                }
                                .onTapGesture {
                                    if selectedKeys.contains(k) {
                                        selectedKeys.remove(k)
                                        persistSelection(for: movie, isSelected: false)
                                    } else if selectedKeys.count < 10 {
                                        selectedKeys.insert(k)
                                        persistSelection(for: movie, isSelected: true)
                                    }
                                }
                                .accessibilityLabel("\(displayTitle(for: movie)) \(selectedKeys.contains(k) ? "selected" : "not selected")")
                            }
                        }
                        .padding()
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 8) {
                            if let error = error {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            Button {
                                saveSelections()
                            } label: {
                                Text("Continue (\(selectedKeys.count)/10)")
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(selectedKeys.count < 10 || isSaving)
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        .background(Material.ultraThin)
                    }
                }
            }
            .navigationTitle("Welcome")
        }
        .task {
            await load()
        }
    }
}

#Preview {
    Hello()
        .environmentObject(AuthViewModel())
}
