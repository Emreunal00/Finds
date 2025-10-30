import SwiftUI

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
                    Label("Home", systemImage: "house.fill")
                }
                .tag(MainTab.home)

            SearchView(resetToken: $searchResetToken)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(MainTab.search)

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(MainTab.chat)

            PickerView()
                .tabItem {
                    Label("Picker", systemImage: "square.grid.2x2")
                }
                .tag(MainTab.picker)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(MainTab.profile)
        }
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
