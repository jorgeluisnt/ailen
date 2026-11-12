import MusicKit
import XCTest
@testable import Ailen

final class AppleMusicAvailabilityTests: XCTestCase {
    func test_missingMusicKitServiceExplainsThePaidAccount() {
        let message = AppleMusicAvailability.catalogMessage(for: MusicTokenRequestError.developerTokenRequestFailed)
        XCTAssertEqual(message, AppleMusicAvailability.musicKitServiceMessage)
        XCTAssertTrue(message.contains("cuenta de desarrollador de Apple de pago"))
        XCTAssertTrue(message.contains("Tu biblioteca sí funciona"))
    }

    func test_tokenErrorsGetSpecificMessages() {
        XCTAssertTrue(AppleMusicAvailability.catalogMessage(for: MusicTokenRequestError.userNotSignedIn).contains("Inicia sesión"))
        XCTAssertTrue(AppleMusicAvailability.catalogMessage(for: MusicTokenRequestError.privacyAcknowledgementRequired).contains("aviso de privacidad"))
        XCTAssertTrue(AppleMusicAvailability.catalogMessage(for: MusicTokenRequestError.permissionDenied).contains("Sin permiso"))
    }

    func test_offlineAndOtherErrors() {
        XCTAssertEqual(AppleMusicAvailability.catalogMessage(for: URLError(.notConnectedToInternet)),
                       "Buscar en Apple Music necesita conexión a internet.")
        struct Other: LocalizedError { var errorDescription: String? { "algo raro" } }
        XCTAssertTrue(AppleMusicAvailability.catalogMessage(for: Other()).hasSuffix("algo raro"))
    }

    func test_authorizationMessages() {
        XCTAssertNil(AppleMusicAvailability.message(forAuthorization: .authorized))
        XCTAssertNotNil(AppleMusicAvailability.message(forAuthorization: .denied))
        XCTAssertNotNil(AppleMusicAvailability.message(forAuthorization: .notDetermined))
    }
}
