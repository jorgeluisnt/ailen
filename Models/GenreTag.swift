import AVFoundation

enum GenreTag {
    /// Genre from the file's full metadata: AVFoundation does not put it in
    /// `commonMetadata`. Identifiers seen on macOS/AVFoundation: FLAC
    /// `vorb/GENRE`, MP4 (AAC/ALAC) `itsk/%A9gen`, MP3 `id3/TCON`, WAV
    /// `caaf/info-genre`.
    static func read(at url: URL) async -> String? {
        guard let items = try? await AVURLAsset(url: url).load(.metadata) else { return nil }
        for item in items {
            guard let id = item.identifier?.rawValue, isGenreIdentifier(id),
                  let raw = try? await item.load(.stringValue),
                  let genre = normalizedGenre(raw) else { continue }
            return genre
        }
        return nil
    }

    static func isGenreIdentifier(_ id: String) -> Bool {
        let id = id.lowercased()
        return id.hasSuffix("genre") || id.hasSuffix("/tcon") || id.hasSuffix("%a9gen")
    }

    /// Trims the tag, drops bare ID3v1 numeric codes such as "(17)" (shown
    /// as unknown rather than guessed), and repairs UTF-8 text that was
    /// decoded as Latin-1 (WAV INFO chunks: "FusiÃ³n" → "Fusión").
    static func normalizedGenre(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        if let bytes = text.data(using: .isoLatin1), let utf8 = String(data: bytes, encoding: .utf8) {
            text = utf8
        }
        let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        guard !text.isEmpty, digits.isEmpty || !digits.allSatisfy(\.isNumber) else { return nil }
        return text
    }
}
