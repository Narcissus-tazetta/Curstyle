import CursorKit
import SwiftUI

enum Motion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.spring(response: 0.3, dampingFraction: 0.88)
    static var reveal: AnyTransition { AnyTransition.opacity.combined(with: .offset(y: -6)) }
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that is skipped under Reduce Motion.
    func motionAnimation(_ animation: Animation = Motion.standard, value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }

    /// 内容を区切るカード。ライトモードでも輪郭が消えないよう細い縁を付け、コントラストを上げる設定では濃くする。
    func cardBackground(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    /// VoiceOver はアイコンだけのボタンを SF Symbol の名前で読むので、ツールチップを読み上げ名にも使う。
    func iconHelp(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}

private struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(increased ? 0.08 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(increased ? 0.35 : 0.07), lineWidth: 1)
            )
    }
}

/// システム設定のサイドバーと同じ、色付きの角丸に白い記号。
struct IconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 状態を短く示す丸いラベル(適用中・アニメなど)。
struct StatusPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .green

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// 押している間だけ少し沈むプレーンなボタン。
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}

/// カーソルを置く下地。黒い縁取りのカーソルも白いカーソルも見分けられるよう、利用者が切り替えられる。
enum PreviewBackdrop: String, CaseIterable, Identifiable {
    case light, dark, checker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: L10n.text("明るい")
        case .dark: L10n.text("暗い")
        case .checker: L10n.text("市松")
        }
    }

    var systemImage: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .checker: "checkerboard.rectangle"
        }
    }
}

struct BackdropView: View {
    let backdrop: PreviewBackdrop
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            switch backdrop {
            case .light:
                shape.fill(Color(white: 0.93))
            case .dark:
                shape.fill(Color(white: 0.16))
            case .checker:
                Canvas { context, size in
                    let cell: CGFloat = 8
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.86)))
                    for row in 0..<Int(ceil(size.height / cell)) {
                        for col in 0..<Int(ceil(size.width / cell)) where (row + col).isMultiple(of: 2) {
                            let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                            context.fill(Path(rect), with: .color(Color(white: 0.72)))
                        }
                    }
                }
                .clipShape(shape)
            }
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct ThemeActionButtonStyle: ButtonStyle {
    var primary = false
    var tinted = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var colorful: Bool { primary || tinted }

    private var colors: [Color] {
        if primary {
            return [Color(red: 0.49, green: 0.46, blue: 0.96), Color(red: 0.35, green: 0.34, blue: 0.86)]
        }
        if tinted {
            return [Color(red: 0.80, green: 0.40, blue: 0.72), Color(red: 0.65, green: 0.32, blue: 0.71)]
        }
        let fill = Color.primary.opacity(0.065)
        return [fill, fill]
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .foregroundStyle(colorful ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: colorful
                                ? [Color.white.opacity(contrast == .increased ? 0.6 : 0.32), Color.white.opacity(0.08)]
                                : [Color.primary.opacity(0.14), Color.primary.opacity(0.08)],
                            startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorful && isEnabled ? 0.12 : 0), radius: 3, y: 2)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Motion.quick, value: configuration.isPressed)
    }
}
