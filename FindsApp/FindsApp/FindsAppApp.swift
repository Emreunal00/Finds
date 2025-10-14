//
//  FindsAppApp.swift
//  FindsApp
//
//  Created by Emre ünal on 13.10.2025.
//

import SwiftUI
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

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}

@main
struct YourApp: App {
  // register app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  // Global tema tercihi
  @AppStorage("themePreference") private var themePreferenceRaw: String = ThemePreference.system.rawValue

  private var themePreference: ThemePreference {
    ThemePreference(rawValue: themePreferenceRaw) ?? .system
  }

  var body: some Scene {
    WindowGroup {
      NavigationView {
        ContentView()
      }
      // Kullanıcı tercihine göre renk şemasını uygula
      .preferredColorScheme(themePreference.colorScheme)
    }
  }
}
