// Color+Rating.swift
import SwiftUI

extension Color {
    // 0-25 red, 26-50 orange, 51-70 yellow, 71-100 green
    static func ratingColor(forPercent percent: Int) -> Color {
        switch percent {
        case ...25:
            return .red
        case 26...50:
            return .orange
        case 51...70:
                return .yellow
        default:
            return .green
        }
    }

    // Eğer puanı 0–10 aralığında saklıyorsanız:
    static func ratingColor(forScore score: Double) -> Color {
        let percent = Int(round(score * 10)) // 0–10 -> 0–100
        return ratingColor(forPercent: percent)
    }
}
