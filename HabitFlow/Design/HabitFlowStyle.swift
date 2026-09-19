import SwiftUI
import HabitCore

enum HFTheme {
    static let ink = Color.adaptive(light: 0x17201C, dark: 0xF2F4EF)
    static let secondaryInk = Color.adaptive(light: 0x69736E, dark: 0xA7B0AA)
    static let background = Color.adaptive(light: 0xF3F4EE, dark: 0x111512)
    static let surface = Color.adaptive(light: 0xFFFEFA, dark: 0x1B211D)
    static let surfaceRaised = Color.adaptive(light: 0xFFFFFF, dark: 0x232A25)
    static let hero = Color.adaptive(light: 0x17201C, dark: 0x1B211D)
    static let accent = Color.adaptive(light: 0x226B4A, dark: 0x71C99B)
    static let lime = Color.adaptive(light: 0xC8E86C, dark: 0xB8D866)
    static let sage = Color.adaptive(light: 0xDCEBD6, dark: 0x263D30)
    static let blueSoft = Color.adaptive(light: 0xE9F1FF, dark: 0x1D2B3E)
    static let orangeSoft = Color.adaptive(light: 0xFFF0E4, dark: 0x3B2B20)
    static let orange = Color.adaptive(light: 0xC96E2E, dark: 0xF0A164)
    static let divider = Color.adaptive(light: 0x17201C, dark: 0xFFFFFF).opacity(0.09)
}

private extension Color {
    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

struct HFCardStyle: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var color: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(HFTheme.ink.opacity(0.055), lineWidth: 1)
            }
    }
}

extension View {
    func hfCard(
        padding: CGFloat = 18,
        radius: CGFloat = 24,
        color: Color = HFTheme.surface
    ) -> some View {
        modifier(HFCardStyle(padding: padding, radius: radius, color: color))
    }
}

struct HFSectionHeader: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(HFTheme.ink)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(HFTheme.secondaryInk)
            }
        }
        .padding(.horizontal, 3)
    }
}

struct HFIconButton: View {
    let systemImage: String
    let accessibilityTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HFTheme.ink)
                .frame(width: 44, height: 44)
                .background(HFTheme.surfaceRaised, in: Circle())
                .overlay { Circle().stroke(HFTheme.ink.opacity(0.06), lineWidth: 1) }
                .shadow(color: HFTheme.ink.opacity(0.08), radius: 12, y: 5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }
}

struct HabitIconView: View {
    let habit: Habit
    var size: CGFloat = 48

    private var color: Color { Color(hex: habit.colorHex) }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.38, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                    .stroke(color.opacity(0.13), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch habit.rule {
        case .healthQuantity(let metric, _):
            switch metric {
            case .steps: return "figure.walk"
            case .activeEnergy: return "flame.fill"
            case .exerciseMinutes: return "figure.run"
            case .distanceWalkRun: return "shoeprints.fill"
            case .water: return "drop.fill"
            }
        case .healthSleep:
            return "moon.zzz.fill"
        case .healthMindful:
            return "figure.mind.and.body"
        case .healthWorkout:
            return "dumbbell.fill"
        case .geofence:
            return "location.fill"
        case .manual:
            return manualSymbol
        }
    }

    private var manualSymbol: String {
        let value = "\(habit.name) \(habit.emoji)".lowercased()
        let mappings: [([String], String)] = [
            (["теннис", "tennis", "🎾"], "figure.tennis"),
            (["трен", "кач", "зал", "gym", "workout", "fitness", "🏋", "💪"], "dumbbell.fill"),
            (["бег", "run", "🏃"], "figure.run"),
            (["ход", "прогул", "walk", "🚶"], "figure.walk"),
            (["растяж", "stretch", "йога", "yoga"], "figure.flexibility"),
            (["вода", "water", "💧"], "drop.fill"),
            (["сон", "sleep", "😴", "🌙"], "moon.zzz.fill"),
            (["чита", "книг", "read", "book", "📚", "📖"], "book.closed.fill"),
            (["медит", "осознан", "mindful", "🧘"], "figure.mind.and.body"),
            (["лекар", "витамин", "pill", "💊"], "pills.fill"),
            (["уч", "курс", "learn", "study", "🎓"], "graduationcap.fill"),
            (["дневник", "пис", "journal", "write", "✍"], "pencil.line"),
            (["убор", "clean", "🧹"], "sparkles")
        ]
        return mappings.first { keywords, _ in keywords.contains { value.contains($0) } }?.1 ?? "checkmark"
    }
}
