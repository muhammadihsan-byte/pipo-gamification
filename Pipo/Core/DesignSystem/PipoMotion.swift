import SwiftUI

/// A small motion vocabulary: quick touch-down, soft release, calm navigation.
/// Motion never owns navigation, persistence, rewards, or completion callbacks.
enum PipoMotion {
    static let press = Animation.easeOut(duration: 0.10)
    static let release = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let selection = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let page = Animation.easeInOut(duration: 0.24)
    static let arrival = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let dissolve = Animation.easeOut(duration: 0.14)
}

enum PipoCompanionReaction: String, Sendable {
    case acknowledge, reassure, celebrate
}

private struct PipoPressFeedback: ViewModifier {
    let pressed: Bool
    let depth: CGFloat
    let scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private var active: Bool { pressed && isEnabled && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? scale : 1)
            .offset(y: active ? depth : 0)
            .animation(reduceMotion ? nil : (pressed ? PipoMotion.press : PipoMotion.release), value: active)
    }
}

struct PipoQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pipoPressFeedback(configuration.isPressed, depth: 0, scale: 0.98)
    }
}

private struct PipoPageTransition<Value: Hashable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .id(value)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
            .animation(reduceMotion ? PipoMotion.dissolve : PipoMotion.page, value: value)
    }
}

private struct PipoValueAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : PipoMotion.selection, value: value)
    }
}

private struct PipoEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? PipoMotion.dissolve : PipoMotion.arrival, value: appeared)
            .onAppear { appeared = true }
    }
}

private struct PipoTabSelection: ViewModifier {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(selected && !reduceMotion ? 1.08 : 1)
            .offset(y: selected && !reduceMotion ? -1 : 0)
            .animation(reduceMotion ? nil : PipoMotion.selection, value: selected)
    }
}

extension View {
    func pipoPressFeedback(_ pressed: Bool, depth: CGFloat = 1, scale: CGFloat = 0.985) -> some View {
        modifier(PipoPressFeedback(pressed: pressed, depth: depth, scale: scale))
    }

    /// Key only the changing page, never a model owner or persistent form state.
    func pipoPageTransition<Value: Hashable>(value: Value) -> some View {
        modifier(PipoPageTransition(value: value))
    }

    func pipoAnimate<Value: Equatable>(_ value: Value) -> some View {
        modifier(PipoValueAnimation(value: value))
    }

    func pipoEntrance() -> some View {
        modifier(PipoEntrance())
    }

    func pipoTabSelection(_ selected: Bool) -> some View {
        modifier(PipoTabSelection(selected: selected))
    }
}

#if DEBUG
/// Deterministic accessibility QA, scoped to Debug. Never disables the OS setting.
struct PipoMotionQAPreferences: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.environment(\.accessibilityReduceMotion,
            reduceMotion || ProcessInfo.processInfo.arguments.contains("-pipo-reduce-motion-qa"))
    }
}
#endif
