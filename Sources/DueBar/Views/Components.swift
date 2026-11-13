import DueKit
import SwiftUI

/// Themed container for the dropdown.
struct Dropdown: View {
    @AppStorage(SettingsKey.theme) private var themeID = PanelTheme.systemID
    @Environment(\.colorScheme) private var colorScheme
    var close: () -> Void
    var initialTab: DropdownContent.Tab = .upcoming
    static let width: CGFloat = 360

    var body: some View {
        let theme = PanelTheme.resolve(themeID, colorScheme: colorScheme)
        DropdownContent(close: close, initialTab: initialTab)
            .padding(6)
            .frame(width: Self.width)
            .background(theme.background)
            .foregroundStyle(theme.text)
            .environment(\.panelTheme, theme)
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }
}

struct SectionBox<Content: View>: View {
    @Environment(\.panelTheme) private var theme
    var title: String?
    var titleColor: Color?
    var trailing: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, color: Color? = nil, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleColor = color
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if title != nil || trailing != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title {
                        Text(title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(titleColor ?? theme.header)
                    }
                    Spacer(minLength: 8)
                    if let trailing {
                        Text(trailing).font(.system(size: 11.5, weight: .medium)).foregroundStyle(theme.secondaryText).monospacedDigit()
                    }
                }
                .padding(.horizontal, 2)
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.section))
    }
}

struct CategoryBadge: View {
    var category: PaymentCategory
    var size: CGFloat = 30

    var body: some View {
        let color = Color(hex: category.colorHex)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.18))
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
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? theme.secondaryText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovering ? theme.track : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

extension Decimal {
    var double: Double { (self as NSDecimalNumber).doubleValue }
}

/// Google profile photo in a circle, falling back to the account's initial.
struct AccountAvatar: View {
    var session: AuthSession
    var size: CGFloat = 40

    private var initial: String { String((session.name.isEmpty ? session.email : session.name).prefix(1)).uppercased() }

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.22))
            Text(initial).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(Color.accentColor)
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
