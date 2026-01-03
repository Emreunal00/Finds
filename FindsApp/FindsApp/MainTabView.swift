import SwiftUI

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

enum MainTab: Int {
    case home = 0
    case search = 1
    case chat = 2
    case picker = 3
    case profile = 4
}

struct MainTabView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var selectedTab: MainTab = .home
    // Aynı sekmeye tekrar dokunmayı algılamak için önceki seçim
    @State private var lastSelectedTab: MainTab = .home

    // SearchView’e reset tetikleyicisi göndermek için bir sayaç
    @State private var searchResetToken: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    VStack {
                        Image(systemName: "house.fill")
                            .renderingMode(.original)
                            .foregroundColor(.primary)
                    }
                }
                .tag(MainTab.home)

            SearchView(resetToken: $searchResetToken)
                .tabItem {
                    VStack {
                        Image(systemName: "magnifyingglass")
                            .renderingMode(.original)
                            .foregroundColor(.primary)
                    }
                }
                .tag(MainTab.search)

            ChatView()
                .tabItem {
                    VStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .renderingMode(.original)
                            .foregroundColor(.primary)
                    }
                }
                .tag(MainTab.chat)

            PickerView()
                .tabItem {
                    VStack {
                        Image(systemName: "gamecontroller.fill")
                            .renderingMode(.original)
                            .foregroundColor(.primary)
                    }
                }
                .tag(MainTab.picker)

            ProfileView()
                .tabItem {
                    VStack {
                        Image(systemName: "person.crop.circle")
                            .renderingMode(.original)
                            .foregroundColor(.primary)
                    }
                }
                .tag(MainTab.profile)
        }
        .tint(.green)
        .onChange(of: selectedTab) { newValue in
            // Aynı tab tekrar seçildiyse ve bu Search tab ise reset tetikle
            if lastSelectedTab == newValue, newValue == .search {
                searchResetToken &+= 1
            }
            lastSelectedTab = newValue
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
}

