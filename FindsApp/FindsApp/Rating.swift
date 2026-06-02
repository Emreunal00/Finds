
import SwiftUI

extension Color {
    
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

    
    static func ratingColor(forScore score: Double) -> Color {
        let percent = Int(round(score * 10)) 
        return ratingColor(forPercent: percent)
    }
}
