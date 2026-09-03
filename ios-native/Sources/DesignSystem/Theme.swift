import SwiftUI

/// The web app's design tokens, ported so the native build reads as the same
/// product. Values mirror `src/styles.css` `:root` (light palette only — the
/// app forces `.preferredColorScheme(.light)` at the root, see `PinpopApp`)
/// — keep them in sync when the web palette changes.
enum Theme {
    // MARK: Brand + ink

    static let coral = Color(hex: 0xFF6847)
    static let pink = Color(hex: 0xFF3F8E)
    static let violet = Color(hex: 0x5B35F2)
    static let yellow = Color(hex: 0xFFD34E)
    static let ink = Color(hex: 0x281F42)
    /// Already the contrast-corrected value (AA on the light ground).
    static let muted = Color(hex: 0x5F5670)
    static let ground = Color(hex: 0xFFF8EF)
    static let surface = Color.white

    // MARK: Surfaces & lines — the rest of `:root`'s surface tokens

    static let surface2 = Color(hex: 0xFAF8FC)
    static let fill = Color(hex: 0xF4F0F6)
    static let fill2 = Color(hex: 0xF6F2F8)
    static let violetSoft = Color(hex: 0xF0EBFF)
    static let line = Color(hex: 0xE8E2ED)
    static let lineSoft = Color(hex: 0xEEE9F1)

    static let dangerSoft = Color(hex: 0xFFF2F2)
    static let dangerLine = Color(hex: 0xF3DDE2)
    static let dangerInk = Color(hex: 0xC0392B)
    static let warnSoft = Color(hex: 0xFFF3E8)
    static let warnInk = Color(hex: 0xA2521F)
    static let infoSoft = Color(hex: 0xEAF6FF)
    static let infoInk = Color(hex: 0x1A6FA8)

    static let toastBg = Color(hex: 0x281F42)
    static let toastInk = Color.white

    /// `.dock button` — a distinct grey the web app never routes through
    /// `--muted`. Kept as its own token so a future `--muted` tweak can't
    /// silently drag the dock's resting-tab color along with it.
    static let dockInactive = Color(hex: 0x7A7189)

    // MARK: Gradients

    /// `.dock .center-action` / `.primary` — `linear-gradient(135deg #ff7b42, #ff3e86)`.
    static let brandGradient = LinearGradient(
        colors: [Color(hex: 0xFF7B42), Color(hex: 0xFF3E86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// `--streak-hot` — the blaze/legend streak-chip background.
    static let streakHotGradient = LinearGradient(
        colors: [Color(hex: 0xFFDCA0), Color(hex: 0xFF9F5A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// `.streak-milestone` / the celebratory pill in `PersonCard`.
    static let streakMilestoneGradient = LinearGradient(
        colors: [Color(hex: 0xFFE08A), Color(hex: 0xFF9F5A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The default (spark/flame-tier) streak badge — `linear-gradient(135deg, #fff1e4, #ffe6f1)`.
    static let streakBaseGradient = LinearGradient(
        colors: [Color(hex: 0xFFF1E4), Color(hex: 0xFFE6F1)],
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
        static let chrome = (color: Color(hex: 0x30234F).opacity(0.16), radius: CGFloat(15), y: CGFloat(10))
        /// `.dock` — `0 20px 60px rgba(45,31,75,.24)`.
        static let dock = (color: Color(hex: 0x2D1F4B).opacity(0.24), radius: CGFloat(30), y: CGFloat(20))
        /// `--shadow` (`.sheet`, `.person-card`, `.map-hint`) —
        /// `0 18px 50px rgba(54,39,94,.18)`.
        static let sheet = (color: Color(hex: 0x36275E).opacity(0.18), radius: CGFloat(25), y: CGFloat(18))
        /// A plain solid-white card (friend rows, message rows) — not a CSS
        /// class of its own, kept close to this file's previous single
        /// shadow so already-shipped screens don't visibly shift.
        static let card = (color: Color(hex: 0x2C1E48).opacity(0.28), radius: CGFloat(30), y: CGFloat(18))
    }

    /// The floating-chrome background a `FloatingCard` style renders —
    /// opaque white for a plain card, or the web app's `--glass`/
    /// `--glass-solid` (translucent white over a real blur) for chrome that
    /// sits on the map.
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
                    .stroke(borderColor, lineWidth: 2)
            )
            .shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .card:
            Theme.surface.opacity(0.97)
        case .glass:
            // `--glass: rgba(255,255,255,.86)` + `backdrop-filter: blur(18px)`
            // — real Material for the blur, a warm white tint on top so it
            // doesn't read as neutral iOS grey against the map.
            ZStack { Rectangle().fill(.thinMaterial); Theme.surface.opacity(0.4) }
        case .glassSolid:
            // `--glass-solid: rgba(255,255,255,.95)` + `blur(22-24px)`.
            ZStack { Rectangle().fill(.regularMaterial); Theme.surface.opacity(0.55) }
        case .dock:
            ZStack { Rectangle().fill(.regularMaterial); Theme.surface.opacity(0.6) }
        }
    }

    private var borderColor: Color {
        style == .card ? .white : .white.opacity(0.7)
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
