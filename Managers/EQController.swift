import Foundation
import Combine

final class EQController: ObservableObject {
    static let bandCount = 10
    static let gainRange: ClosedRange<Float> = -12...12
    /// Bump when `PersistedState`'s on-disk shape needs a migration.
    static let schemaVersion = 1

    @Published private(set) var bands: [Float]
    /// "Directo": the curve is kept but not applied. Persisted.
    @Published private(set) var isDirect: Bool = false
    /// True when audio actually goes through the EQ: not Directo and the
    /// curve does something (a parametric preset or a non-flat graphic curve).
    var isEnabled: Bool { !isDirect && (parametric != nil || bands.contains { $0 != 0 }) }
    /// Active parametric curve (imported AutoEQ profile). Non-nil means the
    /// EQ is in parametric mode and the graphic `bands` are dormant — `apply`
    /// is a no-op until the preset is cleared (the UI hides the faders too).
    @Published private(set) var parametric: ParametricEQPreset?

    /// On-disk shape: the graphic bands plus the optional parametric preset,
    /// persisted as a single-item list through `SchemaStore`.
    private struct PersistedState: Codable {
        let bands: [Float]
        let parametric: ParametricEQPreset?
        /// Optional so files written before the Directo mode still decode.
        let direct: Bool?
    }

    private let store: KeyValueStore
    private var debouncer: Debouncer!

    /// Defaults to an in-memory store so directly-constructed instances (tests,
    /// previews) never touch the real Documents directory; `AriaApp` injects
    /// the file-backed store.
    init(store: KeyValueStore = InMemoryKeyValueStore()) {
        self.store = store
        if let state = SchemaStore.loadItems(PersistedState.self, from: store,
                                             currentVersion: Self.schemaVersion)?.first,
           state.bands.count == Self.bandCount {
            self.bands = state.bands.map { $0.clamped(to: Self.gainRange) }
            self.parametric = state.parametric
            self.isDirect = state.direct ?? false
        } else {
            self.bands = Array(repeating: 0, count: Self.bandCount)
        }
        self.debouncer = Debouncer(delay: 0.5) { [weak self] in self?.performSave() }
    }

    // flush() is a no-op in deinit (its [weak self] is already nil); save direct.
    deinit { if debouncer?.isPending == true { performSave() } }

    @discardableResult
    func apply(_ gains: [Float]) -> EQApplyOutcome {
        guard gains.count == EQController.bandCount else { return .noChange }
        // Parametric mode owns the audio unit's configuration; graphic edits
        // are disabled until the preset is removed.
        guard parametric == nil else { return .noChange }
        let wasEnabled = isEnabled
        let clamped = gains.map { $0.clamped(to: EQController.gainRange) }
        if bands == clamped {
            return .noChange
        }
        bands = clamped
        save()
        return outcome(wasEnabled: wasEnabled)
    }

    /// Switches between Directo and Ecualizador without touching the curve.
    @discardableResult
    func setDirect(_ direct: Bool) -> EQApplyOutcome {
        guard direct != isDirect else { return .noChange }
        let wasEnabled = isEnabled
        isDirect = direct
        save()
        return outcome(wasEnabled: wasEnabled)
    }

    private func outcome(wasEnabled: Bool) -> EQApplyOutcome {
        switch (wasEnabled, isEnabled) {
        case (false, true): return .becameEnabled
        case (true, false): return .becameDisabled
        case (true, true): return .stillEnabled
        case (false, false): return .noChange
        }
    }

    @discardableResult
    func reset() -> Bool {
        let wasEnabled = isEnabled
        bands = Array(repeating: 0, count: EQController.bandCount)
        parametric = nil
        save()
        return wasEnabled
    }

    @discardableResult
    func setBand(_ index: Int, gain: Float) -> EQApplyOutcome {
        guard index >= 0, index < EQController.bandCount else { return .noChange }
        var newBands = bands
        newBands[index] = gain.clamped(to: EQController.gainRange)
        return apply(newBands)
    }

    // MARK: - Parametric

    /// Activates a parametric curve. Choosing a profile means wanting to hear
    /// it, so this also leaves Directo.
    @discardableResult
    func setParametric(_ preset: ParametricEQPreset) -> EQApplyOutcome {
        let wasEnabled = isEnabled
        let unchanged = parametric == preset
        parametric = preset
        isDirect = false
        save()
        if unchanged && wasEnabled { return .noChange }
        return wasEnabled ? .stillEnabled : .becameEnabled
    }

    /// Drops the parametric curve and falls back to the graphic bands (which
    /// may themselves be flat → EQ disables).
    @discardableResult
    func clearParametric() -> EQApplyOutcome {
        guard parametric != nil else { return .noChange }
        let wasEnabled = isEnabled
        parametric = nil
        save()
        if wasEnabled && !isEnabled { return .becameDisabled }
        return isEnabled ? .stillEnabled : .noChange
    }

    // MARK: - Persistence

    func flushPendingWrites() { debouncer?.flush() }

    private func save() { debouncer.call() }

    private func performSave() {
        let state = PersistedState(bands: bands, parametric: parametric, direct: isDirect)
        guard let data = try? SchemaStore.encode([state], schemaVersion: Self.schemaVersion) else { return }
        try? store.save(data)
    }
}

enum EQApplyOutcome: Equatable {
    case noChange
    case becameEnabled
    case stillEnabled
    case becameDisabled
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
