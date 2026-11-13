import DueKit
import SwiftUI

/// Themed container for the dropdown.
struct Dropdown: View {
    @AppStorage(SettingsKey.theme) private var themeID = PanelTheme.systemID
    @Environment(\.colorScheme) private var colorScheme
    var close: () -> Void
    var initialPage: DropdownContent.Page = .home
    static let width: CGFloat = 330

    var body: some View {
        let theme = PanelTheme.resolve(themeID, colorScheme: colorScheme)
        DropdownContent(close: close, initialPage: initialPage)
            .lockGated()
            .padding(10)
            .frame(width: Self.width)
            .background(theme.background)
            .foregroundStyle(theme.text)
            .environment(\.panelTheme, theme)
            .environment(\.themeAccent, theme.primary)
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}

struct CategoryBadge: View {
    var category: PaymentCategory
    var size: CGFloat = 30

    var body: some View {
        let color = Color(hex: category.colorHex)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(color.opacity(0.16))
            Image(systemName: category.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// Icon-only button with a hover highlight, for row actions.
struct IconButton: View {
    @Environment(\.panelTheme) private var theme
    var symbol: String
    var help: String
    var tint: Color?
    var size: CGFloat = 26
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(tint ?? theme.secondaryText)
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? theme.track : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

extension Decimal {
    var double: Double { (self as NSDecimalNumber).doubleValue }
}

/// Google profile photo in a circle, falling back to the account's initial.
struct AccountAvatar: View {
    @Environment(\.themeAccent) private var accent
    var session: AuthSession
    var size: CGFloat = 40

    private var initial: String { String((session.name.isEmpty ? session.email : session.name).prefix(1)).uppercased() }

    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.22))
            Text(initial).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(accent)
            if let url = URL(string: session.picture), !session.picture.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Google sign-in branding

/// Google's "G" mark (multicolour) and the sign-in button built from it, following Google's
/// branding guidelines: the logo stays unaltered, the button is a neutral dark or light
/// surface with a thin outline and the words "Sign in with Google".
enum GoogleBrand {
    private static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48">
    <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
    <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
    <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
    <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
    </svg>
    """

    static let logo: NSImage = NSImage(data: Data(svg.utf8)) ?? NSImage()
}

struct GoogleLogo: View {
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: GoogleBrand.logo)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GoogleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var title: String
    var action: () -> Void

    var body: some View {
        let dark = colorScheme == .dark
        Button(action: action) {
            HStack(spacing: 10) {
                GoogleLogo(size: 18)
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .foregroundStyle(dark ? Color(hex: 0xE3E3E3) : Color(hex: 0x1F1F1F))
            .background(Capsule().fill(dark ? Color(hex: 0x131314) : .white))
            .overlay(Capsule().strokeBorder(dark ? Color(hex: 0x8E918F) : Color(hex: 0x747775), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Brand mark

/// The app logo (Resources/BrandMark.png, copied into the bundle). A dev run from the package
/// folder finds it next to the sources; if it is missing a drawn stand-in is used.
enum BrandLogo {
    static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/BrandMark.png"))
    }()
}

struct BrandMark: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image = BrandLogo.image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Brand.gradient)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Brand.orange.opacity(0.28), radius: size * 0.1, y: size * 0.04)
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

extension View {
    /// The rounded white (or dark) surface that groups rows in the dropdown.
    func cardBackground() -> some View { modifier(CardBackground()) }
}

private struct CardBackground: ViewModifier {
    @Environment(\.panelTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.section))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.track, lineWidth: 1))
            .shadow(color: .black.opacity(theme.isDark ? 0 : 0.04), radius: 6, y: 2)
    }
}

// MARK: - Date and time fields

/// A date shown as a rounded chip that opens a calendar, instead of the system's field with a
/// stepper and a dark pop-up. The calendar follows the window's light/dark mode and the brand accent.
struct DateField: View {
    @Binding var date: Date
    @State private var open = false

    var body: some View {
        FieldChip(text: Self.format(date), symbol: "calendar") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden()
                    .padding(10).frame(width: 250)
                    .tint(Brand.orange)
                    // Picking a day closes the calendar; changing month does not touch `date`.
                    .onChange(of: date) { _, _ in open = false }
            }
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = appLocale
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f.string(from: date)
    }
}

/// A time of day as a chip that opens a clock.
struct TimeField: View {
    @Binding var date: Date
    @State private var open = false

    var body: some View {
        FieldChip(text: Self.format(date), symbol: "clock") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.graphical).labelsHidden()
                    .padding(10)
                    .tint(Brand.orange)
            }
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = appLocale
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

private struct FieldChip: View {
    @Environment(\.themeAccent) private var accent
    var text: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text).monospacedDigit()
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings cards

extension View {
    /// The rounded surface behind grouped rows in the Data tab, matching the dropdown's cards but
    /// built from system colours so it follows the window's light or dark mode.
    func settingsCard() -> some View { modifier(SettingsCard()) }
}

private struct SettingsCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 6, y: 2)
    }
}

/// A rounded pill button with an icon, for secondary actions.
struct PillButton: View {
    @Environment(\.themeAccent) private var accent
    var title: String
    var symbol: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(accent)
                Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(hovering ? 0.1 : 0.06)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension View {
    /// Fades the last few points of a scroll area so a row cut off at the bottom reads as "more below".
    func fadeBottomEdge(_ height: CGFloat = 16) -> some View {
        mask(
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: height)
            }
        )
    }
}

// MARK: - Scroll area that fits its content

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A scroll view exactly as tall as its content up to `maxHeight`: no scroll bar and no bounce
/// when everything fits, and a faded bottom edge plus indicators when it doesn't. (A plain
/// ScrollView with fixedSize and a maximum height reported slightly more than the content, so a
/// single row still got a scroll bar.)
struct FittingScrollView<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    private var overflows: Bool { contentHeight > maxHeight + 0.5 }

    var body: some View {
        ScrollView {
            content.background(
                GeometryReader { proxy in Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height) }
            )
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(overflows ? .automatic : .never)
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : maxHeight)
        .modifier(OptionalFade(active: overflows))
    }
}

private struct OptionalFade: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        if active { content.fadeBottomEdge() } else { content }
    }
}
