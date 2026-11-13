import SwiftUI

private struct FocusSkySurfaceKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var focusSkySurface: Bool {
        get { self[FocusSkySurfaceKey.self] }
        set { self[FocusSkySurfaceKey.self] = newValue }
    }
}

struct Panel<Content: View>: View {
    @Environment(\.focusSkySurface) private var skySurface
    var padding: CGFloat = 24
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).background(Palette.surface.opacity(skySurface ? ThemeOpacity.cardOnSky : 1), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(skySurface ? Palette.outline.opacity(0.50) : Palette.line.opacity(0.8), lineWidth: 1))
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var wide = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: wide ? .infinity : nil)
            .padding(.horizontal, 21).padding(.vertical, 12)
            .foregroundStyle(Palette.onAccent).background(Palette.accent, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain)
    }
}

struct QuietButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Palette.softAccent.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
}

struct IconButton: View {
    let icon: String
    let title: String
    var color: Color = Palette.secondary
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .foregroundStyle(color).frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

struct LogoMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(LinearGradient(colors: [Palette.logoTop, Palette.logoBottom], startPoint: .top, endPoint: .bottom))
            Image(systemName: "leaf").font(.system(size: size * 0.55, weight: .light)).foregroundStyle(Palette.logoGlyph)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
        }
    }
}

struct EmptyNote: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 29, weight: .ultraLight)).foregroundStyle(Palette.accent)
                .frame(width: 64, height: 64).background(Palette.softAccent.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text)
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity)
    }
}
