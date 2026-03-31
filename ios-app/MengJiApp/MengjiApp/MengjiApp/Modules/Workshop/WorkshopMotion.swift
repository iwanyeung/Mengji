import SwiftUI

enum WorkshopMotion {
    static let tapDuration: Double = 0.16
    static let selectDuration: Double = 0.2
    static let navigationSpring = Animation.spring(response: 0.34, dampingFraction: 0.84)
}

struct WorkshopPrimaryCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.986 : 1.0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: WorkshopMotion.tapDuration), value: configuration.isPressed)
    }
}

struct WorkshopSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.992 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: WorkshopMotion.tapDuration), value: configuration.isPressed)
    }
}
