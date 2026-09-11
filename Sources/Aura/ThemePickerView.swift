import SwiftUI

struct ThemePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(alignment: .leading, spacing: BrandSpacing.lg) {
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text("Appearance")
                    .font(.title2.bold())
                Text("Choose an appearance and separate preset palettes for light and dark mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            appearancePicker(
                selection: $preferences.appearanceMode,
                light: AppTheme.find(preferences.lightThemeID),
                dark: AppTheme.find(preferences.darkThemeID)
            )

            Divider()

            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text("Theme library")
                    .font(BrandTypography.cardTitle)
                Text("Select either color preview to assign that preset to light or dark mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210, maximum: 340), spacing: BrandMetrics.gridSpacing)],
                spacing: BrandMetrics.gridSpacing
            ) {
                ForEach(AppTheme.presets) { theme in
                    ThemeCard(
                        theme: theme,
                        lightSelected: preferences.lightThemeID == theme.id,
                        darkSelected: preferences.darkThemeID == theme.id,
                        selectLight: { preferences.lightThemeID = theme.id },
                        selectDark: { preferences.darkThemeID = theme.id }
                    )
                }
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityIdentifier("appearance.theme-picker")
    }

    private func appearancePicker(selection: Binding<AppearanceMode>, light: AppTheme, dark: AppTheme) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    selection.wrappedValue = mode
                } label: {
                    VStack(spacing: BrandSpacing.sm) {
                        AppearanceMiniature(mode: mode, light: light, dark: dark)
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(BrandSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                            .fill(selection.wrappedValue == mode ? theme.subtleAccent(for: colorScheme) : Color.primary.opacity(0.035))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                            .strokeBorder(
                                selection.wrappedValue == mode ? theme.readablePrimary(for: colorScheme) : Color.primary.opacity(0.10),
                                lineWidth: selection.wrappedValue == mode ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == mode ? .isSelected : [])
            }
        }
    }
}

/// Two half-window sketches showing the canvas and accent of the presets actually
/// assigned to light and dark mode, so the appearance switch previews the result
/// instead of a generic navy-and-system-accent window.
private struct AppearanceMiniature: View {
    let mode: AppearanceMode
    let light: AppTheme
    let dark: AppTheme

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if mode != .dark { miniature(theme: light, scheme: .light).frame(width: mode == .system ? proxy.size.width / 2 : proxy.size.width) }
                if mode != .light { miniature(theme: dark, scheme: .dark).frame(width: mode == .system ? proxy.size.width / 2 : proxy.size.width) }
            }
            .clipShape(.rect(cornerRadius: BrandRadius.xxs, style: .continuous))
        }
        .frame(height: 40)
    }

    private func miniature(theme: AppTheme, scheme: ColorScheme) -> some View {
        let isLight = scheme == .light
        return ZStack(alignment: .leading) {
            theme.canvas(for: scheme)
            Rectangle().fill(isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.08)).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(theme.readablePrimary(for: scheme)).frame(width: 28, height: 4)
                Capsule().fill(isLight ? Color.black.opacity(0.14) : Color.white.opacity(0.20)).frame(width: 42, height: 3)
            }
            .padding(.leading, 24)
        }
    }
}

private struct ThemeCard: View {
    let theme: AppTheme
    let lightSelected: Bool
    let darkSelected: Bool
    let selectLight: () -> Void
    let selectDark: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: BrandMetrics.cardContentSpacing) {
            VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                Text(theme.name)
                    .font(.callout.weight(.semibold))
                Text(theme.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: BrandSpacing.sm) {
                ThemeOrb(theme: theme, scheme: .light, selected: lightSelected, action: selectLight)
                ThemeOrb(theme: theme, scheme: .dark, selected: darkSelected, action: selectDark)
            }
        }
        .padding(BrandMetrics.cardPaddingCompact)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.065 : 0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: BrandRadius.md, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovered ? 0.18 : 0.09), lineWidth: 1)
        }
        .onHover { hovered = $0 }
    }
}

private struct ThemeOrb: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: scheme == .light
                                ? [.white, theme.secondaryColor.opacity(0.48), theme.primaryColor.opacity(0.72)]
                                : [theme.darkBackground, theme.primaryColor.opacity(0.82), theme.secondaryColor],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 34
                        )
                    )
                    .frame(width: 38, height: 38)
                if selected {
                    Circle().strokeBorder(theme.primaryColor, lineWidth: 2.5).frame(width: 44, height: 44)
                    Image(systemName: scheme == .light ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(theme.onPrimaryColor)
                        .padding(4)
                        .background(theme.primaryColor, in: .circle)
                        .offset(x: 15, y: 15)
                }
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .help("Use \(theme.name) in \(scheme == .light ? "light" : "dark") mode")
        .accessibilityLabel("\(theme.name), \(scheme == .light ? "light" : "dark") theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
