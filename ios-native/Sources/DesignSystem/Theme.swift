import SwiftUI
import UIKit

/// The web app's design tokens, ported so the native build reads as the same
/// product. Values mirror `src/styles.css` — the `:root` block for light and
/// the `[data-theme='dark']` block for dark. Keep them in sync when the web
/// palette changes.
///
/// Every token is a *dynamic* colour: it resolves per the current interface
/// style, which is the native equivalent of a CSS custom property being
/// redefined under `[data-theme='dark']`. That means dark mode needs no
/// per-screen work — any view already built out of `Theme.*` adapts on its
/// own.
enum Theme {
    // MARK: - Dynamic colour plumbing

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    private static func adaptiveWhite(light: Double, dark: Double) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor.white.withAlphaComponent(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Shadows go black and heavier at night — `--shadow` is
    /// `rgba(0,0,0,.6)` in the dark palette instead of a tinted purple.
    private static func shadow(_ tint: UInt32, light: Double, dark: Double) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(dark)
                : UIColor(rgb: tint).withAlphaComponent(light)
        })
    }

    // MARK: - Brand + ink

    /// Brand accents hold across both themes, except the two darkest, which
    /// the web app lifts so they stay legible on a dark surface.
    static let coral = adaptive(light: 0xFF6847, dark: 0xFF6847)
    static let pink = adaptive(light: 0xFF3F8E, dark: 0xFF6BA6)
    static let violet = adaptive(light: 0x5B35F2, dark: 0xA08AFF)
    static let yellow = adaptive(light: 0xFFD34E, dark: 0xFFD34E)

    static let ink = adaptive(light: 0x281F42, dark: 0xF5F1FA)
    /// Already the contrast-corrected value in both themes.
    static let muted = adaptive(light: 0x5F5670, dark: 0xA79FB8)
    static let ground = adaptive(light: 0xFFF8EF, dark: 0x14111C)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1E1A29)

    // MARK: - Surfaces & lines

    static let surface2 = adaptive(light: 0xFAF8FC, dark: 0x241F31)
    static let fill = adaptive(light: 0xF4F0F6, dark: 0x2A2438)
    static let fill2 = adaptive(light: 0xF6F2F8, dark: 0x322A44)
    static let violetSoft = adaptive(light: 0xF0EBFF, dark: 0x2A2150)
    static let line = adaptive(light: 0xE8E2ED, dark: 0x342C46)
    static let lineSoft = adaptive(light: 0xEEE9F1, dark: 0x2C2540)

    static let dangerSoft = adaptive(light: 0xFFF2F2, dark: 0x3A1F25)
    static let dangerLine = adaptive(light: 0xF3DDE2, dark: 0x55303A)
    static let dangerInk = adaptive(light: 0xC0392B, dark: 0xFF9D92)
    static let warnSoft = adaptive(light: 0xFFF3E8, dark: 0x3A2A1C)
    static let warnInk = adaptive(light: 0xA2521F, dark: 0xFFBE86)
    static let infoSoft = adaptive(light: 0xEAF6FF, dark: 0x1B3448)
    static let infoInk = adaptive(light: 0x1A6FA8, dark: 0x8FD0FF)

    /// The toast is always a dark pill with a light label, so at night it
    /// lifts *off* the ground rather than reusing `--ink`.
    static let toastBg = adaptive(light: 0x281F42, dark: 0x3A3252)
    static let toastInk = adaptive(light: 0xFFFFFF, dark: 0xF7F4FB)

    /// `.dock button` — a distinct grey the web app never routes through
    /// `--muted`. The CSS leaves it at `#7a7189` at night too, which lands
    /// around 3.4:1 on the dark dock; native lifts it to the dark palette's
    /// `--muted` so a 10px bold label still clears AA.
    static let dockInactive = adaptive(light: 0x7A7189, dark: 0xA79FB8)

    /// `--rim-glass` — the hairline on floating chrome: nearly opaque white
    /// in daylight, a faint 10% highlight at night.
    static let rimGlass = adaptiveWhite(light: 0.86, dark: 0.10)

    // MARK: - Gradients

    /// `.dock .center-action` / `.primary` — a brand gradient, identical in
    /// both themes.
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFF7B42), Color(hex: 0xFF3E86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// `--streak-hot` — the blaze/legend streak background.
    static let streakHotGradient = LinearGradient(
        colors: [adaptive(light: 0xFFDCA0, dark: 0x7A4A12), adaptive(light: 0xFF9F5A, dark: 0xA35C1F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The celebratory milestone pill. The web app leaves this bright in both
    /// themes, which puts the dark palette's pale `--warn-ink` on a pale
    /// orange gradient; darkening it at night keeps the label readable.
    static let streakMilestoneGradient = LinearGradient(
        colors: [adaptive(light: 0xFFE08A, dark: 0x7A4A12), adaptive(light: 0xFF9F5A, dark: 0xA35C1F)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The default (spark/flame-tier) streak badge — same reasoning as above.
    static let streakBaseGradient = LinearGradient(
        colors: [adaptive(light: 0xFFF1E4, dark: 0x33261C), adaptive(light: 0xFFE6F1, dark: 0x33222B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Radius {
        /// `.sheet` / `.person-card` top corners.
        static let card: CGFloat = 30
        /// `.dock`.
        static let dock: CGFloat = 28
        /// `.friend-row` / `.zone-row-main`.
        static let row: CGFloat = 18
        /// `.chip`.
        static let chip: CGFloat = 13
        /// `.feature-grid > button` / `.stat-card`.
        static let tile: CGFloat = 21
    }

    /// The three distinct `box-shadow` recipes the web app actually uses for
    /// floating chrome, kept separate rather than one shared value — CSS
    /// never reused `--shadow` for the dock or the topbar's circle buttons,
    /// each has its own color/blur/offset.
    enum Shadow {
        /// `.circle-button` / `.profile-chip` / `.map-tools button` —
        /// `0 10px 30px rgba(48,35,79,.16)`.
        static let chrome = (color: Theme.shadow(0x30234F, light: 0.16, dark: 0.5), radius: CGFloat(15), y: CGFloat(10))
        /// `.dock` — `0 20px 60px rgba(45,31,75,.24)`.
        static let dock = (color: Theme.shadow(0x2D1F4B, light: 0.24, dark: 0.6), radius: CGFloat(30), y: CGFloat(20))
        /// `--shadow` (`.sheet`, `.person-card`, `.map-hint`) —
        /// `0 18px 50px rgba(54,39,94,.18)`, `rgba(0,0,0,.6)` at night.
        static let sheet = (color: Theme.shadow(0x36275E, light: 0.18, dark: 0.6), radius: CGFloat(25), y: CGFloat(18))
        /// A plain solid card (friend rows, message rows) — not a CSS class
        /// of its own.
        static let card = (color: Theme.shadow(0x2C1E48, light: 0.28, dark: 0.55), radius: CGFloat(30), y: CGFloat(18))
    }

    /// The floating-chrome background a `FloatingCard` style renders —
    /// opaque for a plain card, or the web app's `--glass`/`--glass-solid`
    /// (translucent over a real blur) for chrome that sits on the map.
    enum ChromeStyle {
        case card, glass, glassSolid, dock
    }

    enum Font {
        // Real bundled weights sliced from the same two families the web app
        // loads from Google Fonts (`Fredoka`, `DM Sans`) — see
        // Sources/Resources/Fonts/. `Font.custom` silently falls back to the
        // system font if a name isn't found, so a missing bundle/plist entry
        // degrades gracefully rather than crashing.
        static func display(_ size: CGFloat) -> SwiftUI.Font {
            .custom("Fredoka-Bold", size: size)
        }
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .semibold) -> SwiftUI.Font {
            .custom(dmSansName(for: weight), size: size)
        }
        private static func dmSansName(for weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .heavy, .black: return "DMSans-ExtraBold"
            case .bold: return "DMSans-Bold"
            case .semibold: return "DMSans-SemiBold"
            default: return "DMSans-Medium"
            }
        }
    }

    /// `.avatar-photo` / `.avatar` are a rounded square ("squircle"), not a
    /// circle — `border-radius: 16px` on a 46px box, ratio ≈ .348, which
    /// holds close enough across every other size the web app uses (70→25,
    /// 86→30) to stand in as one formula rather than a per-size lookup
    /// table. Map pins and story rings are the deliberate exception — see
    /// `AvatarShape.circle` at their call sites.
    static func avatarRadius(for size: CGFloat) -> CGFloat { size * 0.348 }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// `Color(hex:)` lives in Sources/Shared/ColorHex.swift — it is compiled into
// the widget extension too, so it must not be duplicated here.

/// The soft floating card used for sheets, the dock and the person card.
struct FloatingCard: ViewModifier {
    var radius: CGFloat = Theme.Radius.card
    var style: Theme.ChromeStyle = .card

    func body(content: Content) -> some View {
        content
            // `.background(_:in:)` only accepts a `ShapeStyle` (Color,
            // Gradient, Material…) — the glass styles below are a composed
            // *View* (Material layered under a translucency tint), so this
            // uses the View-based `.background { }` overload and clips it to
            // the rounded shape by hand instead.
            .background {
                background.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.rimGlass, lineWidth: 2)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .card:
            Theme.surface.opacity(0.97)
        case .glass:
            // `--glass` + `backdrop-filter: blur(18px)` — real Material for
            // the blur, a surface tint on top so it doesn't read as neutral
            // iOS grey against the map. Material is already theme-aware, so
            // this darkens on its own at night.
            ZStack { Rectangle().fill(.thinMaterial); Theme.surface.opacity(0.4) }
        case .glassSolid:
            ZStack { Rectangle().fill(.regularMaterial); Theme.surface.opacity(0.55) }
        case .dock:
            ZStack { Rectangle().fill(.regularMaterial); Theme.surface.opacity(0.6) }
        }
    }

    private var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
        switch style {
        case .card: return Theme.Shadow.card
        case .glass: return Theme.Shadow.chrome
        case .glassSolid: return Theme.Shadow.sheet
        case .dock: return Theme.Shadow.dock
        }
    }
}

extension View {
    func floatingCard(radius: CGFloat = Theme.Radius.card, style: Theme.ChromeStyle = .card) -> some View {
        modifier(FloatingCard(radius: radius, style: style))
    }

    /// Uniform press feedback, matching the `:active` scale added on the web.
    func pressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(PressableStyle(scale: scale))
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
