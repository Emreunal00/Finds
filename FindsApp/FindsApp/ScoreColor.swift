import SwiftUI

enum ScoreColor {
    static func color(for percent: Int) -> Color {
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
}
