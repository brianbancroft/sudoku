import SwiftUI
import UIKit

enum Palette {
    static let canvas = dynamic(light: 0xE7E0D4, dark: 0x100E0C)
    static let board = dynamic(light: 0xFBF7F0, dark: 0x1B1815)
    static let card = dynamic(light: 0xFBF7F0, dark: 0x221E1A)
    static let ink = dynamic(light: 0x1C1612, dark: 0xF6F1E8)
    static let entry = dynamic(light: 0x0E4F5C, dark: 0x8ED4DE)
    static let muted = dynamic(light: 0x4E463C, dark: 0xC8BEB0, lightHigh: 0x2A241C, darkHigh: 0xFFFFFF)
    static let note = dynamic(light: 0x3F382F, dark: 0xE4D9C8, lightHigh: 0x241C16, darkHigh: 0xFFFFFF)
    static let line = dynamic(light: 0xD4CBBC, dark: 0x3C352C, lightHigh: 0x8A7F70, darkHigh: 0xB7AA9A)
    static let lineStrong = dynamic(light: 0x2A241E, dark: 0xE8E0D4)
    static let selection = dynamic(light: 0xF0D08A, dark: 0x4C3D24)
    static let hint = dynamic(light: 0xE2B15A, dark: 0x6A5428)
    static let related = dynamic(light: 0xF3EBDD, dark: 0x2A241E)
    static let sameNumber = dynamic(light: 0xD5E4DE, dark: 0x1A2E2C)
    static let conflictFill = dynamic(light: 0xF3D2CB, dark: 0x4A2C28)
    static let conflictInk = dynamic(light: 0x7A241E, dark: 0xF3B8B0)
    static let accent = dynamic(light: 0x0E4F5C, dark: 0xE4C48A)
    static let primaryButton = dynamic(light: 0x1C1612, dark: 0xF3E6C8)
    static let primaryButtonText = dynamic(light: 0xFBF7F0, dark: 0x1C1612)

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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(prominent ? Palette.primaryButton : Palette.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Palette.ink, lineWidth: 1.5)
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
