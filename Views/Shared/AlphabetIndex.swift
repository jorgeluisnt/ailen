import SwiftUI

/// A–Z (with Ñ) + "#" jump index for long lists, like Contacts.
enum AlphabetIndex {
    static let letters: [String] = "ABCDEFGHIJKLMNÑOPQRSTUVWXYZ".map(String.init) + ["#"]

    /// Index letter for a title: first character, accents removed (but Ñ
    /// kept, it is its own letter in Spanish); anything else is "#".
    static func letter(for text: String?) -> String {
        guard let first = text?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let upper = String(first).uppercased()
        if upper == "Ñ" { return "Ñ" }
        let folded = upper.folding(options: .diacriticInsensitive, locale: nil)
        return letters.contains(folded) ? folded : "#"
    }

    /// First item id per letter, in list order.
    static func anchors<T>(_ items: [T], letter: (T) -> String, id: (T) -> AnyHashable) -> [String: AnyHashable] {
        var result: [String: AnyHashable] = [:]
        for item in items {
            let key = letter(item)
            if result[key] == nil { result[key] = id(item) }
        }
        return result
    }

    /// The letter to jump to: itself if present, else the next present one,
    /// else the previous one (Contacts behaviour).
    static func target(for letter: String, in available: Set<String>) -> String? {
        guard let start = letters.firstIndex(of: letter) else { return nil }
        if let next = letters[start...].first(where: available.contains) { return next }
        return letters[..<start].last(where: available.contains)
    }
}

/// The vertical strip. Tap or drag across it; letters without items are
/// dimmed and jump to the nearest available one.
struct AlphabetIndexBar: View {
    let available: Set<String>
    let tokens: DesignTokens
    let onSelect: (String) -> Void

    static let width: CGFloat = 22

    @State private var lastLetter: String?

    var body: some View {
        GeometryReader { geo in
            let rowHeight = min(16, geo.size.height / CGFloat(AlphabetIndex.letters.count))
            VStack(spacing: 0) {
                ForEach(AlphabetIndex.letters, id: \.self) { letter in
                    Text(letter)
                        .font(.system(size: min(11, rowHeight * 0.75), weight: .semibold))
                        .foregroundColor(available.contains(letter)
                                         ? tokens.highlightColor
                                         : tokens.textSecondary.opacity(0.35))
                        .frame(width: Self.width, height: rowHeight)
                }
            }
            .padding(.vertical, 4)
            .glassSurface(in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let top = (geo.size.height - rowHeight * CGFloat(AlphabetIndex.letters.count)) / 2
                        let index = Int((value.location.y - top - 4) / rowHeight)
                        let clamped = min(max(index, 0), AlphabetIndex.letters.count - 1)
                        jump(to: AlphabetIndex.letters[clamped])
                    }
                    .onEnded { _ in lastLetter = nil }
            )
        }
        .frame(width: Self.width + 4)
        .accessibilityElement()
        .accessibilityLabel("Índice alfabético")
        .accessibilityValue(lastLetter ?? "")
        .accessibilityHint("Desliza hacia arriba o abajo para saltar a una letra")
        .accessibilityAdjustableAction { direction in
            let present = AlphabetIndex.letters.filter(available.contains)
            guard !present.isEmpty else { return }
            let current = lastLetter.flatMap { present.firstIndex(of: $0) }
            let next: Int
            switch direction {
            case .increment: next = current.map { min($0 + 1, present.count - 1) } ?? 0
            case .decrement: next = current.map { max($0 - 1, 0) } ?? 0
            @unknown default: return
            }
            lastLetter = present[next]
            onSelect(present[next])
        }
    }

    private func jump(to letter: String) {
        guard let target = AlphabetIndex.target(for: letter, in: available), target != lastLetter else { return }
        lastLetter = target
        Haptics.selection()
        onSelect(target)
    }
}
