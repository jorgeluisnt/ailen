import Foundation

enum ImportError: Error, LocalizedError {
    case unsupportedFormat(format: AudioFormat)
    case fileNotDownloaded
    case zeroByteFile

    var format: AudioFormat {
        switch self {
        case .unsupportedFormat(let format): return format
        case .fileNotDownloaded, .zeroByteFile: return .unknown
        }
    }

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "El formato \(format.displayName) no es compatible."
        case .fileNotDownloaded:
            return "El archivo aún no ha terminado de descargarse de iCloud."
        case .zeroByteFile:
            return "El archivo está vacío (0 bytes)."
        }
    }
}
