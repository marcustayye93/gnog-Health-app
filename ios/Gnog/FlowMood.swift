import SwiftUI

// Shared display constants for flow + mood logging (matches the PWA).
enum LogOptions {
    static let flows = ["spotting", "light", "medium", "heavy"]
    static let flowEmoji: [String: String] = [
        "spotting": "💧", "light": "🩸", "medium": "🩸🩸", "heavy": "🩸🩸🩸",
    ]
    static let moods = ["happy", "calm", "energetic", "anxious", "sad", "irritable", "tired", "cramps"]
    static let moodEmoji: [String: String] = [
        "happy": "😊", "calm": "😌", "energetic": "⚡", "anxious": "😟",
        "sad": "😢", "irritable": "😠", "tired": "😴", "cramps": "🤕",
    ]

    static func flowLabel(_ f: String) -> String {
        (flowEmoji[f] ?? "") + " " + f.capitalized
    }
    static func moodLabel(_ m: String) -> String {
        (moodEmoji[m] ?? "") + " " + m.capitalized
    }
}

// Small reusable chip button.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
