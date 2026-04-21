//
//  FindsAppApp.swift
//  FindsApp
//
//  Created by Emre ünal on 13.10.2025.
//

import SwiftUI
import Combine
import FirebaseCore

enum ThemePreference: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  var displayName: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
}

@MainActor
final class ThemeStore: ObservableObject {
  @Published var preference: ThemePreference {
    didSet {
      UserDefaults.standard.set(preference.rawValue, forKey: Self.storageKey)
    }
  }

  private static let storageKey = "themePreference"

  init() {
    let storedValue = UserDefaults.standard.string(forKey: Self.storageKey)
    self.preference = ThemePreference(rawValue: storedValue ?? "") ?? .system
  }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}

@main
struct YourApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  @StateObject private var authVM = AuthViewModel()
  @StateObject private var themeStore = ThemeStore()
  @State private var shouldShowLaunchProfilePicker = false
  @State private var lastAuthenticatedUserID: String?

  var body: some Scene {
    WindowGroup {
      Group {
        if authVM.user != nil {
          if shouldShowLaunchProfilePicker {
            LaunchProfilePickerView(
              profiles: authVM.user?.profiles ?? [],
              currentProfileID: authVM.currentProfile?.id
            ) { profile in
              shouldShowLaunchProfilePicker = false
              authVM.selectProfile(profile.id)
            }
          } else {
            MainTabView()
          }
        } else {
          AuthView()
        }
      }
      .preferredColorScheme(themeStore.preference.colorScheme)
      .environmentObject(authVM)
      .environmentObject(themeStore)
      .onAppear {
        syncLaunchProfileRequirement(for: authVM.user)
      }
      .onChange(of: authVM.user) { user in
        syncLaunchProfileRequirement(for: user)
      }
    }
  }

  private func syncLaunchProfileRequirement(for user: UserProfile?) {
    guard let user else {
      shouldShowLaunchProfilePicker = false
      lastAuthenticatedUserID = nil
      return
    }

    let uid = user.id
    if uid != lastAuthenticatedUserID {
      lastAuthenticatedUserID = uid
      shouldShowLaunchProfilePicker = user.profiles.count > 1
    }
  }
}
