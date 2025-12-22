import SwiftUI

struct CustomLoadingView: View {
    var message: String? = nil
    @State private var animate = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Neon glow behind spinner
                Circle()
                    .fill(
                        RadialGradient(colors: [Color.green.opacity(0.45), Color.green.opacity(0.15), .green],
                                       center: .center,
                                       startRadius: 2,
                                       endRadius: 80)
                    )
                    .frame(width: 90, height: 90)
                    .blur(radius: 18)
                    .scaleEffect(animate ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animate)
                    .accessibilityHidden(true)

                // Spinner strokes
                ZStack {
                    SpinnerArc(startAngle: .degrees(0), endAngle: .degrees(110))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(animate ? 360 : 0))
                        .shadow(color: Color.green.opacity(0.8), radius: 8, x: 0, y: 0)
                        .shadow(color: Color.green.opacity(0.5), radius: 16, x: 0, y: 0)

                    SpinnerArc(startAngle: .degrees(180), endAngle: .degrees(290))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(animate ? 360 : 0))
                        .shadow(color: Color.green.opacity(0.8), radius: 8, x: 0, y: 0)
                        .shadow(color: Color.green.opacity(0.5), radius: 16, x: 0, y: 0)
                }
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(message ?? "Loading")
    }
}

// Yardımcı Arc shape’i
struct SpinnerArc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: radius,
                    startAngle: startAngle - .degrees(90),
                    endAngle: endAngle - .degrees(90),
                    clockwise: false)
        return path
    }
}
