import SwiftUI
import UIKit
import AVKit

/// The website's "mac" skin (css/skin-mac/, and the /audio page), in SwiftUI.
///
/// Every value here is the website's own: the colours are its tokens, and each
/// `MacType` is one of its text rules (face, weight, px size, line-height,
/// letter-spacing in em, case) carried over 1:1 — a CSS px is an iOS point.
/// Where a value comes from, the rule is named beside it.
enum Mac {
    // dark (css/skin-mac/base.css --md-*): the map's chrome
    static let desk  = Color(rgb: 0x17181A)
    static let face  = Color(rgb: 0x3A3B3E)
    static let field = Color(rgb: 0x28292B)
    static let ink   = Color(rgb: 0xE4E6EA)
    static let dim   = Color(rgb: 0xA0A1A5)
    static let hair  = Color(rgb: 0x4D4E52)

    // light, "mac light" (--mac-*): the drawer's windows
    static let desktop = Color(rgb: 0x2F3032)
    static let window  = Color(rgb: 0xC2C2C6)
    static let card    = Color(rgb: 0xE0E0E4)
    static let cardInk = Color(rgb: 0x16171A)
    static let cardDim = Color(rgb: 0x26282C)
    static let line    = Color(rgb: 0x9B9BA1)
    static let rail    = Color.white
    static let shadow  = Color.black.opacity(0.58)

    // shared
    static let coral = Color(rgb: 0xE8545C)   // --mac-accent, --mac-off
    static let heat  = Color(rgb: 0xA8252C)   // --mac-heat (/audio's --deep)
    static let on    = Color(rgb: 0x38A057)   // --mac-on
    static let lamp  = Color(rgb: 0xFF3333)   // .live.is-on i
    static let creditGrey = Color(rgb: 0xC9CCD2) // .settings-drawer-credit in the drawer
    static let barSubtitle = Color.white.opacity(0.88)   // /audio .brand .s

    /// The 36 pt of every square button (--mac-btn).
    static let btn: CGFloat = 36
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

// MARK: - type

/// One CSS text rule.
struct MacType {
    enum Face { case main, chicago, mono, display }
    var face: Face
    var size: CGFloat
    var weight: Font.Weight = .regular
    /// CSS line-height, as a multiple of the size.
    var lineHeight: CGFloat = 1.2
    /// CSS letter-spacing, in em.
    var tracking: CGFloat = 0
    var upper = false

    /// The website's "Main" is Johnston100 W03. It is used when the font files are
    /// in the bundle (see Resources/Fonts/README.md); otherwise the system face.
    static let johnston: Bool = UIFont(name: "Johnston100W03-Medium", size: 12) != nil

    private var fontName: String? {
        switch face {
        case .main: Self.johnston ? (weight == .regular ? "Johnston100W03-Regular" : "Johnston100W03-Medium") : nil
        case .chicago: "ChicagoFLF"
        case .mono: weight == .bold ? "RobotoMono-Bold" : "RobotoMono-Regular"
        case .display: "Fraunces-SemiBold"
        }
    }

    var font: Font {
        if let fontName { return .custom(fontName, fixedSize: size) }
        return .system(size: size, weight: weight)
    }

    var uiFont: UIFont {
        if let fontName, let f = UIFont(name: fontName, size: size) { return f }
        let w: UIFont.Weight = weight == .bold ? .bold : weight == .semibold ? .semibold : weight == .medium ? .medium : .regular
        return .systemFont(ofSize: size, weight: w)
    }

    var kern: CGFloat { size * tracking }
    func sized(_ s: CGFloat) -> MacType { var t = self; t.size = s; return t }

    /// Width of `text` set in this type, less the letter-spacing that trails the
    /// last letter (js/ui/skin-mac.js ink()).
    func inkWidth(_ text: String) -> CGFloat {
        let s = upper ? text.uppercased() : text
        let w = (s as NSString).size(withAttributes: [.font: uiFont, .kern: kern]).width
        return w - kern
    }
    /// The CSS `ch` unit: the width of "0".
    var ch: CGFloat { ("0" as NSString).size(withAttributes: [.font: uiFont]).width }
}

extension MacType {
    // /audio
    static let barTitle    = MacType(face: .main, size: 17, weight: .medium, lineHeight: 1.1, tracking: 0.22, upper: true)  // .brand .t
    static let barSubtitle = MacType(face: .chicago, size: 12, lineHeight: 1.1, upper: true)                                  // .brand .s (fitted)
    static let body        = MacType(face: .main, size: 15, weight: .medium, lineHeight: 1.45)                                // body
    static let hero        = MacType(face: .main, size: 14, lineHeight: 1.45)                                                 // .hero p
    static let status      = MacType(face: .chicago, size: 12, lineHeight: 1.3, tracking: 0.05, upper: true)                 // .status
    static let live        = MacType(face: .chicago, size: 12, lineHeight: 1, tracking: 0.06, upper: true)                   // .live
    static let clockLabel  = MacType(face: .chicago, size: 11, lineHeight: 1, tracking: 0.06, upper: true)                   // .clock span
    static let clockValue  = MacType(face: .mono, size: 13, weight: .bold, lineHeight: 1, tracking: 0.02)                    // .clock
    static let secHead     = MacType(face: .main, size: 12, weight: .medium, lineHeight: 1.2, tracking: 0.08, upper: true)  // .sec h2
    static let button      = MacType(face: .main, size: 14, weight: .medium, lineHeight: 1.2)                                // .btn
    static let gridButton  = MacType(face: .main, size: 13, weight: .medium, lineHeight: 1.2)                                // .grid4 .btn
    static let countdown   = MacType(face: .mono, size: 14, weight: .bold, lineHeight: 1)                                    // .countdown
    static let credit      = MacType(face: .main, size: 13, lineHeight: 1.45)                                                // .credit
    static let modalP      = MacType(face: .main, size: 15, lineHeight: 1.55)                                                // .modal-body p
    static let question    = MacType(face: .chicago, size: 18, lineHeight: 1)                                                // .q
    // the drawer (css/skin-mac/drawer.css, final cascade)
    static let cardHead    = MacType(face: .chicago, size: 13, lineHeight: 1.2, tracking: 0.04, upper: true)                 // .mac-drawer-card > heading
    static let drawerRow   = MacType(face: .main, size: 14, weight: .medium, lineHeight: 1.25)                               // .cp-check, .settings-link-btn
    static let drawerNote  = MacType(face: .main, size: 13, lineHeight: 1.45)                                                // .settings-mode-diff-body p
    static let drawerCredit = MacType(face: .main, size: 12, lineHeight: 1.35, tracking: 0.02)                               // .settings-drawer-credit
    static let creditLink  = MacType(face: .chicago, size: 12, lineHeight: 1.2, tracking: 0.02)                              // .settings-credit-link
    static let aboutSection = MacType(face: .main, size: 13, weight: .medium, lineHeight: 1.2, tracking: 0.08, upper: true) // .about-panel-section
    static let aboutText   = MacType(face: .main, size: 15, lineHeight: 1.55)                                                // .about-panel-body p, li
    static let aboutNote   = MacType(face: .main, size: 13, lineHeight: 1.55)                                                // .about-panel-note
    static let switchLabel = MacType(face: .chicago, size: 10, weight: .bold, lineHeight: 1, tracking: 0.06, upper: true)   // .effect-power-bezel::after
    // the map's chrome (css/skin-mac/nav.css)
    static let navLabel    = MacType(face: .chicago, size: 12, lineHeight: 1, tracking: 0.02, upper: true)                   // .map-nav-btn
    static let option      = MacType(face: .mono, size: 11, weight: .bold, lineHeight: 1.2, upper: true)                     // .map-sleep-option
    static let tooltip     = MacType(face: .mono, size: 10, weight: .bold, lineHeight: 1.35, upper: true)                    // .mac-tip
    // the one display face: the current key
    static let key         = MacType(face: .display, size: 34, weight: .semibold, lineHeight: 1.05)
}

extension View {
    /// Sets text in a `MacType`: face, tracking, case, and the CSS line box
    /// (line spacing between lines, half-leading above and below).
    func macType(_ t: MacType) -> some View {
        let natural = t.uiFont.lineHeight
        let box = t.size * t.lineHeight
        return self
            .font(t.font)
            .tracking(t.kern)
            .textCase(t.upper ? .uppercase : nil)
            .lineSpacing(max(0, box - natural))
            .padding(.vertical, (box - natural) / 2)
    }
}

// MARK: - the hard shadow and the edge

enum MacPalette {
    case dark, light
    var fill: Color { self == .dark ? Mac.field : Mac.card }
    var ink: Color { self == .dark ? Mac.ink : Mac.cardInk }
    var shadow: Color { self == .dark ? Mac.ink : Mac.shadow }
}

extension View {
    /// A 1 px edge and a hard offset shadow with no blur (--md-lift / --mac-lift).
    func macEdge(_ palette: MacPalette = .dark, lift: CGFloat = 2) -> some View {
        macEdge(edge: palette.ink, shadow: palette.shadow, lift: lift)
    }
    func macEdge(edge: Color, shadow: Color, lift: CGFloat) -> some View {
        self
            .overlay(Rectangle().strokeBorder(edge, lineWidth: 1))
            .background(Rectangle().fill(shadow).offset(x: lift, y: lift))
    }
}

// MARK: - the button

/// mac-theme's button (.btn, .md-btn): a field, a 1 px edge, a 2 px hard shadow;
/// pressed, it moves a pixel into its shadow (:active translate(1px, 1px), the
/// shadow 1 px). A toggle that is on is green with white on it. The coral hover
/// is for a mouse only (@media (hover: hover)), so on a phone there is none.
struct MacButtonStyle: ButtonStyle {
    var palette: MacPalette = .dark
    var isOn = false
    var minHeight: CGFloat = 36
    var horizontalPadding: CGFloat = 12
    var lift: CGFloat = 2
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        let press: CGFloat = pressed ? 1 : 0
        configuration.label
            .foregroundStyle(isOn ? .white : palette.ink)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: minHeight)
            .background(isOn ? Mac.on : palette.fill)
            .overlay(Rectangle().strokeBorder(palette.ink, lineWidth: 1))
            .background(Rectangle().fill(palette.shadow).offset(x: lift - press, y: lift - press))
            .offset(x: press, y: press)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == MacButtonStyle {
    static var mac: MacButtonStyle { MacButtonStyle() }
    static func mac(_ palette: MacPalette = .dark, on: Bool = false, minHeight: CGFloat = 36,
                    padding: CGFloat = 12, lift: CGFloat = 2) -> MacButtonStyle {
        MacButtonStyle(palette: palette, isOn: on, minHeight: minHeight, horizontalPadding: padding, lift: lift)
    }
    /// .btn-light .btn-sq: the square light button on a coral bar.
    static var macSquareLight: MacButtonStyle { MacButtonStyle(palette: .light, minHeight: 32, horizontalPadding: 0) }
}

// MARK: - the website's icons, from their SVG paths (24 × 24 view box)

struct MacIcon: Shape {
    enum Kind { case play, pause, close, back, mapGrid }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func poly(_ pts: [(CGFloat, CGFloat)]) { p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) }); p.closeSubpath() }
        switch kind {
        case .play:  poly([(8, 5), (8, 19), (19, 12)])                                               // M8 5v14l11-7z
        case .pause: poly([(7, 5), (11, 5), (11, 19), (7, 19)]); poly([(13, 5), (17, 5), (17, 19), (13, 19)])
        case .close: poly([(19, 6.41), (17.59, 5), (12, 10.59), (6.41, 5), (5, 6.41), (10.59, 12), (5, 17.59),
                           (6.41, 19), (12, 13.41), (17.59, 19), (19, 17.59), (13.41, 12)])
        case .back:  poly([(15.41, 7.41), (14, 6), (8, 12), (14, 18), (15.41, 16.59), (10.83, 12)])
        case .mapGrid:                                                                                // /audio "Open the Map"
            p.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 16), cornerSize: CGSize(width: 1.5, height: 1.5))
            p.addRect(CGRect(x: 5, y: 6, width: 4.5, height: 4.5))
            p.addRect(CGRect(x: 11.5, y: 6, width: 7.5, height: 4.5))
            p.addRect(CGRect(x: 5, y: 12.5, width: 4.5, height: 5.5))
            p.addRect(CGRect(x: 11.5, y: 12.5, width: 7.5, height: 5.5))
        }
        let s = min(rect.width, rect.height) / 24
        return p.applying(CGAffineTransform(scaleX: s, y: s).translatedBy(x: rect.minX / s, y: rect.minY / s))
    }

    /// Drawn at `size` with the website's fill rule.
    static func view(_ kind: Kind, size: CGFloat) -> some View {
        MacIcon(kind: kind).fill(style: FillStyle(eoFill: kind == .mapGrid)).frame(width: size, height: size)
    }
}

// MARK: - title and subtitle

/// A panel's title over its Chicago subtitle, the subtitle sized to exactly the
/// title's width (js/ui/skin-mac.js fitPair: size = base × title ink ÷ subtitle ink).
struct MacTitle: View {
    let title: String
    var subtitle: String?
    var titleColor: Color = .white
    var subtitleColor: Color = Mac.barSubtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {                                   // .brand gap: 3px
            Text(title).macType(.barTitle).foregroundStyle(titleColor).lineLimit(1).fixedSize()
            if let subtitle {
                Text(subtitle).macType(Self.fitted(title: title, subtitle: subtitle))
                    .foregroundStyle(subtitleColor).lineLimit(1).fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    static func fitted(title: String, subtitle: String) -> MacType {
        let base = MacType.barSubtitle
        let want = MacType.barTitle.inkWidth(title), have = base.inkWidth(subtitle)
        guard want > 0, have > 0 else { return base }
        return base.sized((base.size * want / have * 100).rounded() / 100)
    }
}

// MARK: - windows

/// A window (/audio .win): the face, a 1 px ink edge, a 3 px hard shadow, and a
/// coral title bar (.bar: padding 12 14, a 1 px ink rule under it).
struct MacWindow<Trailing: View, Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                MacTitle(title: title, subtitle: subtitle)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Mac.coral)
            .overlay(alignment: .bottom) { Rectangle().fill(Mac.ink).frame(height: 1) }
            content()
                .padding(.horizontal, 14)                                              // .body: 16px 14px 14px
                .padding(.top, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Mac.face)
        .foregroundStyle(Mac.ink)
        .macEdge(lift: 3)
    }
}

extension MacWindow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// One of the drawer's light windows (.mac-drawer-card): padding 11 13 13, and a
/// Chicago heading over a hairline (padding-bottom 9, margin-bottom 12).
struct MacCard<Content: View>: View {
    let heading: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading).macType(.cardHead)
                .foregroundStyle(Mac.cardInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(Mac.line).frame(height: 1) }
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Mac.window)
        .foregroundStyle(Mac.cardInk)
        .macEdge(.light)
    }
}

/// A section in a window (/audio .sec): a hair rule, padding-top 12, and the
/// heading (margin-bottom 10).
struct MacSection<Content: View>: View {
    let heading: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading).macType(.secHead).foregroundStyle(Mac.ink)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Mac.hair).frame(height: 1) }
    }
}

// MARK: - the switch

/// The Audio Controls switch (base.css .effect-power-*): a 62 × 24 bed, coral
/// with OFF or green with ON, centred in the room beside an 18 × 18 knob whose
/// grips are 1 px ink lines 4 px apart; the knob slides in .14 s.
struct MacSwitchStyle: ToggleStyle {
    var palette: MacPalette = .light

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                bed(on: configuration.isOn)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }

    private func bed(on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Rectangle().fill(on ? Mac.on : Mac.coral)
            Text(on ? "ON" : "OFF").macType(.switchLabel).foregroundStyle(.white)
                .frame(width: 60 - 22)                     // the inner 60, less the knob's 22
            knob.padding(2).frame(maxWidth: .infinity, alignment: on ? .leading : .trailing)
        }
        .padding(1)
        .frame(width: 62, height: 24)
        .macEdge(palette)
        .animation(.timingCurve(0.32, 0.72, 0.35, 1, duration: 0.14), value: on)
    }

    private var knob: some View {
        Rectangle()
            .fill(Mac.card)
            .overlay(Rectangle().strokeBorder(Mac.cardInk, lineWidth: 1))
            .overlay {
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Mac.cardInk).frame(width: 1) } }
                    .frame(height: 9)
            }
            .frame(width: 18, height: 18)
    }
}

// MARK: - LIVE

/// /audio .live: 30 tall, padding 0 12, gap 8, a 9 px lamp. On, the word is
/// coral and the lamp #ff3333, pulsing to .3 and back over 1.6 s.
struct MacLiveBadge: View {
    let isOn: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? Mac.lamp : Mac.dim)
                .frame(width: 9, height: 9)
                .opacity(isOn && pulse && !reduceMotion ? 0.3 : 1)
            Text("Live").macType(.live)
        }
        .foregroundStyle(isOn ? Mac.coral : Mac.dim)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Mac.field)
        .macEdge()
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOn ? "Live, playing" : "Live, not playing")
    }
}

// MARK: - the screen

/// A page on the desk (/audio body: padding 20 16, the column at most 440 wide).
struct MacPage<Content: View>: View {
    var background: Color = Mac.desk
    var maxWidth: CGFloat = 440
    var spacing: CGFloat = 18
    var horizontal: CGFloat = 16
    var vertical: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, horizontal)
                .padding(.vertical, vertical)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(background.ignoresSafeArea())
        .macStatusBar(background)
    }
}

extension View {
    /// The status bar sits on `color`, not on whatever scrolls under it.
    func macStatusBar(_ color: Color) -> some View {
        overlay(alignment: .top) { color.frame(height: 0).background(color.ignoresSafeArea(edges: .top)) }
    }
}

/// The AirPlay and Bluetooth picker, as a square dark button.
struct MacRoutePicker: View {
    var body: some View {
        RoutePickerView()
            .frame(width: Mac.btn, height: Mac.btn)
            .background(Mac.field)
            .macEdge()
            .accessibilityLabel("Choose where to play")
    }
}

private struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Mac.ink)
        v.activeTintColor = UIColor(Mac.on)
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
