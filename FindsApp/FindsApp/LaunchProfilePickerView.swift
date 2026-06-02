import SwiftUI

struct LaunchProfilePickerView: View {
    let profiles: [Profile]
    let currentProfileID: String?
    let onSelect: (Profile) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 24)

                VStack(spacing: 8) {
                    Text("Choose a Profile")
                        .font(.largeTitle.bold())
                    Text("Select who is using Finds right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 20)], spacing: 24) {
                    ForEach(profiles) { profile in
                        Button {
                            onSelect(profile)
                        } label: {
                            VStack(spacing: 10) {
                                LaunchProfileAvatar(
                                    profile: profile,
                                    isSelected: profile.id == currentProfileID
                                )
                                Text(profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? profile.displayName! : "Profile")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 96)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationBarHidden(true)
        }
    }
}

private struct LaunchProfileAvatar: View {
    let profile: Profile
    let isSelected: Bool

    var body: some View {
        Group {
            if let urlStr = profile.photoURL {
                if urlStr.hasPrefix("avatar://") {
                    let id = String(urlStr.dropFirst("avatar://".count))
                    Image(id)
                        .resizable()
                        .scaledToFill()
                } else if let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            placeholder
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 28))
            }
    }
}
