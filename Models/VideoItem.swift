import Foundation

/// A folder the user linked in Videos. Videos inside it are reached through
/// this one security-scoped bookmark, so nothing is copied into the app.
struct VideoSource: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var bookmark: Data
}

/// A linked video. Either inside a linked folder (`sourceID` +
/// `relativePath`, e.g. "Viajes/2024/playa.mp4") or a single linked file
/// (`fileBookmark`). The video itself is never copied.
struct VideoItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var sourceID: UUID?
    var relativePath: String?
    var fileBookmark: Data?
    /// Folder below the linked folder ("Viajes/2024"; "" = directly in it).
    /// For single files, the name of the file's folder.
    var folderPath: String?
    var importedAt: Date
    var fileSizeBytes: Int64
    var durationSeconds: Double?
    /// JPEG in `VideoLibraryManager.thumbnailsDirectory`.
    var thumbnailFileName: String?
    /// Where to continue; `nil` = from the start.
    var resumePosition: Double?
    /// The original can't be reached right now (moved away, deleted, iCloud
    /// not downloaded, disk disconnected).
    var isMissing: Bool = false

    var fileExtension: String {
        ((relativePath ?? title) as NSString).pathExtension.uppercased()
    }
}

/// Persisted shape of the video index (one item through `SchemaStore`).
struct VideoLibraryState: Codable {
    var sources: [VideoSource]
    var videos: [VideoItem]
}

/// What the importer learns from a file before linking it.
struct VideoProbe: Equatable {
    var durationSeconds: Double?
    var title: String?
}

enum VideoImportError: Error, Equatable {
    case unsupportedFormat(ext: String)
    case notPlayable
    case fileNotDownloaded
    case zeroByteFile
    case unavailable

    func message(fileName: String) -> String {
        switch self {
        case .unsupportedFormat(let ext):
            let shown = ext.isEmpty ? "ese formato" : ext.uppercased()
            return "\(fileName): \(shown) no es compatible. Usa MP4, MOV o M4V."
        case .notPlayable:
            return "\(fileName) no se puede reproducir en este dispositivo (sin pista de video o códec no compatible)."
        case .fileNotDownloaded:
            return "\(fileName) está en iCloud y no se ha descargado. Ábrelo en la app Archivos para descargarlo."
        case .zeroByteFile:
            return "\(fileName) está vacío (0 bytes)."
        case .unavailable:
            return "\(fileName) no está disponible: se movió, se borró, está en iCloud sin descargar o en un disco desconectado."
        }
    }
}

enum VideoResume {
    /// Position worth remembering: nothing in the first 5 s or past 95 %.
    static func position(current: Double, duration: Double?) -> Double? {
        guard current.isFinite, current >= 5 else { return nil }
        if let duration, duration > 0, current >= duration * 0.95 { return nil }
        return current
    }
}
