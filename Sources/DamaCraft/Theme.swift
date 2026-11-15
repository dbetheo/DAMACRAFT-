import SwiftUI
import AppKit

// MARK: - App info
enum AppInfo {
    static let repo = "dbetheo/DAMACRAFT-"
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
    /// User-Agent envoyé aux API publiques (PaperMC Fill exige un UA explicite avec un contact).
    static var userAgent: String { "DamaCraft/\(version) (https://github.com/\(repo))" }
}

// MARK: - Accent themes
enum AccentTheme: String, CaseIterable, Identifiable {
    case purple, cyan, green, orange, pink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .purple: return "Violet"
        case .cyan: return "Cyan"
        case .green: return "Vert"
        case .orange: return "Orange"
        case .pink: return "Rose"
        }
    }

    var color: Color {
        switch self {
        case .purple: return Color(red: 0.56, green: 0.35, blue: 0.98)
        case .cyan: return Color(red: 0.20, green: 0.74, blue: 0.95)
        case .green: return Color(red: 0.25, green: 0.80, blue: 0.50)
        case .orange: return Color(red: 0.98, green: 0.58, blue: 0.20)
        case .pink: return Color(red: 0.96, green: 0.38, blue: 0.68)
        }
    }

    var deep: Color {
        switch self {
        case .purple: return Color(red: 0.35, green: 0.25, blue: 0.90)
        case .cyan: return Color(red: 0.12, green: 0.40, blue: 0.85)
        case .green: return Color(red: 0.10, green: 0.50, blue: 0.40)
        case .orange: return Color(red: 0.85, green: 0.30, blue: 0.20)
        case .pink: return Color(red: 0.62, green: 0.22, blue: 0.80)
        }
    }
}

// MARK: - Design tokens
enum DC {
    static let bg = Color(red: 0.04, green: 0.045, blue: 0.07)
    static let surface = Color.white.opacity(0.045)
    static let surfaceStrong = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.08)
    static let cyan = Color(red: 0.25, green: 0.85, blue: 0.95)
    static let green = Color(red: 0.3, green: 0.85, blue: 0.55)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let red = Color(red: 1.0, green: 0.38, blue: 0.40)
    static let textSec = Color.white.opacity(0.5)
    static let textTer = Color.white.opacity(0.32)
    static let radius: CGFloat = 14

    private(set) static var theme: AccentTheme = .purple

    /// Appelé au début du body racine : les vues enfants lisent ensuite la couleur à jour.
    @discardableResult
    static func apply(_ name: String) -> Bool {
        theme = AccentTheme(rawValue: name) ?? .purple
        return true
    }

    static var accent: Color { theme.color }
    static var accentDeep: Color { theme.deep }
    static var accentDim: Color { theme.color.opacity(0.18) }
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [theme.color, theme.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Components
struct DCCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DC.surface)
            .clipShape(RoundedRectangle(cornerRadius: DC.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DC.radius, style: .continuous)
                    .stroke(DC.border, lineWidth: 1)
            )
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(DC.textSec)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

struct EmptyState: View {
    let title: String
    let icon: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DC.accent.opacity(0.6))
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if let message {
                Text(message)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(DC.textSec)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(DC.surface)
        .clipShape(RoundedRectangle(cornerRadius: DC.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DC.radius, style: .continuous)
                .stroke(DC.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Button styles
struct ChipButtonStyle: ButtonStyle {
    var tint: Color?
    @Environment(\.isEnabled) private var isEnabled

    init(tint: Color? = nil) { self.tint = tint }

    func makeBody(configuration: Configuration) -> some View {
        let base = tint ?? Color.white
        return configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(base.opacity(configuration.isPressed ? 0.20 : (tint == nil ? 0.07 : 0.14)))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(base.opacity(tint == nil ? 0.09 : 0.35), lineWidth: 1)
            )
            .foregroundStyle(tint ?? Color.white.opacity(0.9))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color?
    @Environment(\.isEnabled) private var isEnabled

    init(color: Color? = nil) { self.color = color }

    func makeBody(configuration: Configuration) -> some View {
        let fill: AnyShapeStyle = {
            if let color { return AnyShapeStyle(color.opacity(0.92)) }
            return AnyShapeStyle(LinearGradient(colors: [DC.accent, DC.accentDeep], startPoint: .leading, endPoint: .trailing))
        }()
        return configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(isEnabled ? fill : AnyShapeStyle(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: isEnabled ? (color ?? DC.accent).opacity(0.3) : .clear, radius: 8, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Field style
extension View {
    func dcField() -> some View {
        self
            .textFieldStyle(.plain)
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DC.border, lineWidth: 1)
            )
    }

    func dcPanel(cornerRadius: CGFloat = DC.radius) -> some View {
        self
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DC.border, lineWidth: 1)
            )
    }
}

// MARK: - Console colouring
func consoleColor(_ line: String) -> Color {
    let l = line.lowercased()
    if line.hasPrefix(">") || line.hasPrefix("[RCON]") { return DC.cyan }
    if l.contains("error") || l.contains("exception") || l.contains("severe") || l.contains("erreur") { return DC.red.opacity(0.95) }
    if l.contains("warn") { return DC.amber.opacity(0.9) }
    if l.contains("joined the game") { return DC.green }
    if l.contains("left the game") { return Color.yellow.opacity(0.85) }
    if l.contains("/info") { return Color.white.opacity(0.72) }
    return Color.white.opacity(0.55)
}

// MARK: - Logo
/// Logo de l'app : l'icône du bundle (DamaCraft.icns), avec un repli sur un cube SF Symbols.
struct AppLogo: View {
    var size: CGFloat = 40

    var body: some View {
        if let icon = NSApp?.applicationIconImage, icon.isValid, Bundle.main.bundleIdentifier != nil {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(DC.accentGradient)
                Image(systemName: "cube.fill")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}
