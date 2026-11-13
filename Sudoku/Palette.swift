import SwiftUI
import UIKit

enum Palette {
    static let canvasTop = dynamic(light: 0xFBEAF1, dark: 0x3A1C2A)
    static let canvas = dynamic(light: 0xF6E4EC, dark: 0x2A1520)
    static let board = dynamic(light: 0xFFF8FB, dark: 0x3A1E2C)
    static let card = dynamic(light: 0xFFF6F9, dark: 0x432433)
    static let ink = dynamic(light: 0x3A2430, dark: 0xFFE8F1)
    static let entry = dynamic(light: 0x8E2348, dark: 0xFFC0D4)
    static let muted = dynamic(light: 0x6B4454, dark: 0xC98BA0, lightHigh: 0x4A2C38, darkHigh: 0xFFE8F1)
    static let note = dynamic(light: 0x6A3E50, dark: 0xF6D5E2, lightHigh: 0x3A2430, darkHigh: 0xFFFFFF)
    static let line = dynamic(light: 0xE7C9D4, dark: 0x6A3A4E, lightHigh: 0x8E2348, darkHigh: 0xF3D5E0)
    static let lineStrong = dynamic(light: 0x5C3144, dark: 0xF3D5E0)
    static let selection = dynamic(light: 0xF4C3D4, dark: 0x6E3450)
    static let hint = dynamic(light: 0xE892B0, dark: 0x8A4564)
    static let related = dynamic(light: 0xFBE4EC, dark: 0x4A2838)
    static let sameNumber = dynamic(light: 0xF6D0E0, dark: 0x5A3044)
    static let conflictFill = dynamic(light: 0xF6D7CC, dark: 0x5A2E32)
    static let conflictInk = dynamic(light: 0x7A2420, dark: 0xFFD4CC)
    static let accent = dynamic(light: 0xB4235A, dark: 0xF0A0C0)
    static let primaryButton = dynamic(light: 0x8E1E4A, dark: 0xF3B6CC)
    static let primaryButtonText = dynamic(light: 0xFFF7FA, dark: 0x3A1524)
    static let success = dynamic(light: 0x8E1E4A, dark: 0xF3B6CC)

    static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightHigh: UInt32? = nil,
        darkHigh: UInt32? = nil
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            let hex: UInt32
            if traits.userInterfaceStyle == .dark {
                hex = high ? (darkHigh ?? dark) : dark
            } else {
                hex = high ? (lightHigh ?? light) : light
            }
            return UIColor(hex: hex)
        })
    }
}

enum Radius {
    static let card: CGFloat = 22
    static let control: CGFloat = 18
    static let key: CGFloat = 16
    static let board: CGFloat = 18
}

enum Space {
    static let screen: CGFloat = 24
    static let stack: CGFloat = 16
    static let tight: CGFloat = 8
}

enum Elevation {
    static func card(_ content: some View) -> some View {
        content.shadow(color: Color(red: 0.35, green: 0.12, blue: 0.22).opacity(0.08), radius: 16, y: 8)
    }
}

struct BlushCanvas: View {
    var body: some View {
        LinearGradient(
            colors: [Palette.canvasTop, Palette.canvas],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

enum TimeFormat {
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append("\(hours) " + (hours == 1 ? "hour" : "hours"))
        }
        parts.append("\(minutes) " + (minutes == 1 ? "minute" : "minutes"))
        parts.append("\(seconds) " + (seconds == 1 ? "second" : "seconds"))
        return parts.joined(separator: ", ")
    }
}

struct InkButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(prominent ? Palette.primaryButtonText : Palette.ink)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(prominent ? Palette.primaryButton : Palette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Palette.accent, lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BannerButtonStyle: ButtonStyle {
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(prominent ? Palette.primaryButtonText : Palette.ink)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(prominent ? Palette.primaryButton : Palette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Palette.ink, lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct PressOpacityStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
