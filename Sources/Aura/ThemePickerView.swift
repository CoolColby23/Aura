import SwiftUI

/// Appearance settings: the light/dark mode switch, then the theme library.
/// The library edits one mode at a time, so each swatch can show exactly how
/// that theme will look on the canvas it is being chosen for.
struct AppearanceSettingsSections: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingScheme: EditingScheme?

    enum EditingScheme: String, CaseIterable, Identifiable {
        case light = "Light Mode"
        case dark = "Dark Mode"
        var id: Self { self }
        var colorScheme: ColorScheme { self == .light ? .light : .dark }
    }

    var body: some View {
        @Bindable var preferences = model.preferences
        let scheme = editingScheme ?? (colorScheme == .dark ? .dark : .light)
        Section("Appearance") {
            HStack(spacing: BrandMetrics.gridSpacing) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceModeCard(
                        mode: mode,
                        light: AppTheme.find(preferences.lightThemeID),
                        dark: AppTheme.find(preferences.darkThemeID),
                        selected: preferences.appearanceMode == mode
                    ) {
                        preferences.appearanceMode = mode
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
        Section {
            Picker("Choose a theme for", selection: Binding(get: { scheme }, set: { editingScheme = $0 })) {
                ForEach(EditingScheme.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 124, maximum: 180), spacing: BrandMetrics.gridSpacing)],
                spacing: BrandMetrics.gridSpacing
            ) {
                ForEach(AppTheme.presets) { theme in
                    let selectedID = scheme == .light ? preferences.lightThemeID : preferences.darkThemeID
                    ThemeSwatch(theme: theme, scheme: scheme.colorScheme, selected: AppTheme.validatedID(selectedID) == theme.id) {
                        if scheme == .light {
                            preferences.lightThemeID = theme.id
                        } else {
                            preferences.darkThemeID = theme.id
                        }
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        } header: {
            Text("Theme")
        } footer: {
            Text("Aura keeps one theme for light mode and one for dark mode, and switches with your Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("appearance.theme-picker")
    }
}

private struct AppearanceModeCard: View {
    let mode: AppearanceMode
    let light: AppTheme
    let dark: AppTheme
    let selected: Bool
    let action: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: BrandSpacing.sm) {
                AppearanceMiniature(mode: mode, light: light, dark: dark)
                    .overlay {
                        RoundedRectangle(cornerRadius: BrandRadius.xs, style: .continuous)
                            .strokeBorder(
                                selected ? theme.readablePrimary(for: colorScheme) : BrandColors.hairline,
                                lineWidth: selected ? 2.5 : 1
                            )
                    }
                Text(mode.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) appearance")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Window sketches showing the canvas and accent of the themes actually
/// assigned to light and dark mode, so the switch previews the result.
private struct AppearanceMiniature: View {
    let mode: AppearanceMode
    let light: AppTheme
    let dark: AppTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if mode != .dark { miniature(theme: light, scheme: .light) }
                if mode != .light {
                    miniature(theme: dark, scheme: .dark)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: mode == .system ? proxy.size.width / 2 : proxy.size.width)
                        }
                }
            }
            .clipShape(.rect(cornerRadius: BrandRadius.xs, style: .continuous))
        }
        .aspectRatio(1.55, contentMode: .fit)
    }

    private func miniature(theme: AppTheme, scheme: ColorScheme) -> some View {
        let isLight = scheme == .light
        let ink: Color = isLight ? .black : .white
        return ZStack(alignment: .topLeading) {
            theme.canvas(for: scheme)
            RadialGradient(colors: [theme.secondaryColor.opacity(0.25), .clear], center: .topTrailing, startRadius: 0, endRadius: 90)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ink.opacity(isLight ? 0.05 : 0.07))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Circle().stroke(theme.haloShading(), lineWidth: 2.5).frame(width: 14, height: 14)
                    Capsule().fill(theme.readablePrimary(for: scheme)).frame(width: 34, height: 4)
                    Capsule().fill(ink.opacity(0.18)).frame(width: 48, height: 3)
                    Capsule().fill(ink.opacity(0.12)).frame(width: 40, height: 3)
                }
                .padding(.top, 8)
            }
            .padding(6)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let selected: Bool
    let action: () -> Void
    @Environment(\.appTheme) private var activeTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                ZStack {
                    theme.canvas(for: scheme)
                    RadialGradient(
                        colors: [theme.secondaryColor.opacity(scheme == .dark ? 0.35 : 0.28), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                    // Each theme shown as its own halo, the one place its colors
                    // are allowed to sweep.
                    BrandMark()
                        .environment(\.appTheme, theme)
                        .frame(width: 40, height: 40)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(theme.onPrimaryColor, theme.primaryColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(7)
                    }
                }
                .frame(height: 76)
                .clipShape(.rect(cornerRadius: BrandRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: BrandRadius.sm, style: .continuous)
                        .strokeBorder(
                            selected ? activeTheme.readablePrimary(for: colorScheme) : BrandColors.hairline,
                            lineWidth: selected ? 2.5 : 1
                        )
                }
                .scaleEffect(hovered && !selected ? 1.02 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name)
                        .font(.callout.weight(.semibold))
                    Text(theme.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { hovered = hovering } }
        .help("Use \(theme.name) in \(scheme == .light ? "light" : "dark") mode")
        .accessibilityLabel("\(theme.name), \(theme.description)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
