import Foundation
import MusicKit

/// Spanish messages for what can and can't be done with Apple Music.
/// Pure, so it can be tested without Apple Music.
enum AppleMusicAvailability {
    /// Catalog search and "add to library" go through the MusicKit service,
    /// which is enabled on the App ID and needs a paid developer account.
    static let musicKitServiceMessage =
        "Buscar en el catálogo y añadir a tu biblioteca necesitan el servicio MusicKit activado para esta app, y eso requiere una cuenta de desarrollador de Apple de pago. Tu biblioteca sí funciona."

    static let subscriptionMessage =
        "Para reproducir canciones del catálogo necesitas una suscripción a Apple Music."

    static func message(forAuthorization status: MusicAuthorization.Status) -> String? {
        switch status {
        case .authorized: return nil
        case .denied, .restricted:
            return "Sin permiso para Apple Music. Actívalo en Ajustes de iOS → Ailen → Medios y Apple Music."
        case .notDetermined: return "Ailen necesita tu permiso para usar Apple Music."
        @unknown default: return "No se pudo comprobar el permiso de Apple Music."
        }
    }

    static func catalogMessage(for error: Error) -> String {
        if let token = error as? MusicTokenRequestError {
            switch token {
            case .developerTokenRequestFailed: return musicKitServiceMessage
            case .permissionDenied: return message(forAuthorization: .denied) ?? ""
            case .userNotSignedIn: return "Inicia sesión con tu Apple ID en la app Música para usar el catálogo."
            case .privacyAcknowledgementRequired: return "Abre la app Música y acepta el aviso de privacidad de Apple Music."
            case .userTokenRevoked, .userTokenRequestFailed:
                return "Apple Music no pudo verificar tu cuenta. Abre la app Música y vuelve a intentarlo."
            case .unknown: break
            @unknown default: break
            }
        }
        if let url = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(url.code) {
            return "Buscar en Apple Music necesita conexión a internet."
        }
        return "No se pudo usar el catálogo de Apple Music: \(error.localizedDescription)"
    }
}
