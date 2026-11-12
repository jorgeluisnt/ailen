import SwiftUI
import UniformTypeIdentifiers

struct EqualizerView: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var eq: EQController
    @EnvironmentObject private var savedProfiles: SavedEQProfilesManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var state: EqualizerState
    @State private var showAutoEQBrowser = false
    @State private var showAutoEQImporter = false
    @State private var pendingFileImport = false
    @State private var importError: String?

    init() {
        // The view is bound to the env-injected `EQController`, but
        // `init()` runs before env objects are available. The throwaway
        // bands here are immediately replaced on first `onAppear` via
        // `state.syncFromController(eq)`.
        _state = StateObject(wrappedValue: EqualizerState(
            initialBands: Array(repeating: 0, count: 10),
            debounceDelay: 0.4,
            onApply: { _ in }
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    modeSection
                    Group {
                    if let preset = eq.parametric {
                        parametricActiveView(preset)
                    } else {
                        presetsBar
                        eqGrid
                            .frame(maxHeight: .infinity)
                        // Saved headphone profiles are reachable from the
                        // graphic screen too — switching to one is how you get
                        // back into parametric mode after removing a profile.
                        savedProfilesSection(active: nil)
                            .padding(.horizontal, DS.Spacing.lg)
                        autoEQRow
                        resetButton
                            .padding(.bottom, DS.Spacing.xl)
                    }
                    }
                    // Directo keeps the curve; it is just not applied.
                    .disabled(eq.isDirect)
                    .opacity(eq.isDirect ? 0.4 : 1)
                }
            }
            .navigationTitle("Ecualizador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Listo") { dismiss() }
                        .foregroundColor(themeManager.theme.accentColor)
                }
            }
        }
        .onAppear {
            // Wire the live-apply path *before* the first sync. `onApply`
            // was a permanent no-op at init (the env-injected
            // `playerManager` isn't available there); assign it here so
            // drags, presets, and Reset reach the audio while the sheet
            // is open — not only on dismiss.
            state.onApply = { gains in playerManager.applyEQPreset(gains) }
            // First appear with the real env-injected controller.
            // The throwaway bands from `init()` are replaced here.
            state.syncFromController(eq)
        }
        .onChange(of: eq.bands) { _ in
            // External mutation (e.g. another view, future lock-screen
            // handler, programmatic reset) — pull the new bands into
            // the draft state. `syncFromController` is a no-op when a
            // debounce is pending so an in-progress drag is preserved.
            state.syncFromController(eq)
        }
        .onDisappear {
            // Fader drags are debounced (only presets/reset apply
            // synchronously), so dismissing within the debounce window would
            // otherwise drop the last adjustment. Cancel the pending timer and
            // flush the current draft directly if it hasn't reached the audio.
            // Skipped in parametric mode — the faders are dormant there and a
            // stale draft must not stomp the imported curve.
            state.cancelPending()
            if eq.parametric == nil && state.localBands != eq.bands {
                playerManager.applyEQPreset(state.localBands)
            }
        }
        .sheet(isPresented: $showAutoEQBrowser, onDismiss: {
            // The browser's folder button defers to the file importer; a sheet
            // can't present another sheet, so chain it through onDismiss.
            if pendingFileImport {
                pendingFileImport = false
                showAutoEQImporter = true
            }
        }) {
            AutoEQBrowserView(
                activeProfileName: eq.parametric?.name,
                onApply: { applyProfile($0) },
                onImportFile: { pendingFileImport = true }
            )
        }
        .fileImporter(isPresented: $showAutoEQImporter,
                      allowedContentTypes: [.plainText, .text],
                      allowsMultipleSelection: false) { result in
            handleAutoEQImport(result)
        }
        .alert("Importar AutoEQ", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Directo / Ecualizador

    /// Sound Wave header switch: on = Ecualizador, off = Directo.
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Toggle(isOn: Binding(
                get: { !eq.isDirect },
                set: { enabled in
                    let direct = !enabled
                    // Push a pending drag first so leaving EQ can't drop it.
                    state.cancelPending()
                    if !direct, eq.parametric == nil, state.localBands != eq.bands {
                        playerManager.applyEQPreset(state.localBands)
                    }
                    playerManager.setAudioMode(direct: direct)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eq.isDirect ? "Directo" : "Ecualizador")
                        .font(DS.Typography.titleMedium)
                        .foregroundColor(themeManager.textPrimary)
                    Text(eq.isDirect ? "Sin ecualización" : "Activado")
                        .font(DS.Typography.caption)
                        .foregroundColor(themeManager.textSecondary)
                }
            }
            .tint(themeManager.tokens.highlightColor)
            .accessibilityLabel("Ecualizador")
            .accessibilityValue(eq.isDirect ? "Desactivado, modo Directo" : "Activado")

            Text(modeExplanation)
                .font(.caption)
                .foregroundColor(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.lg)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var modeExplanation: String {
        if eq.isDirect {
            return "Directo: sin ecualización. iOS puede seguir procesando el audio (volumen, mezcla, conversión de frecuencia), así que no es salida bit-perfect garantizada."
        }
        if let preset = eq.parametric {
            return "El ecualizador modifica el audio. Preamplificación del perfil: \(Self.dB(preset.preamp))."
        }
        let preamp = EQHeadroom.preamp(frequencies: PlayerManager.eqFrequencies, gains: state.localBands)
        guard preamp < 0 else {
            return "El ecualizador modifica el audio. Con la curva plana no se aplica procesamiento."
        }
        return "El ecualizador modifica el audio. Preamplificación automática \(Self.dB(preamp)) para evitar saturación; el volumen general baja en consecuencia."
    }

    private static func dB(_ value: Float) -> String {
        String(format: "%+.1f dB", value)
    }

    /// Sound Wave: "Preset" title with a dropdown.
    private var presetsBar: some View {
        let current = EQPreset.allCases.first { $0.gains == state.localBands }
        return HStack {
            Text("Preset")
                .font(DS.Typography.titleLarge)
                .foregroundColor(themeManager.textPrimary)
            Spacer()
            Menu {
                ForEach(EQPreset.allCases) { preset in
                    Button {
                        state.applyPreset(preset.gains)
                    } label: {
                        if preset == current {
                            Label(preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(preset.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    Text(current?.displayName ?? "Personalizado")
                        .font(DS.Typography.bodyEm)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundColor(themeManager.textPrimary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .glassSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
            }
            .accessibilityLabel("Preset: \(current?.displayName ?? "Personalizado")")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var eqGrid: some View {
        HStack(alignment: .bottom, spacing: 0) {
            dbScaleColumn
            ForEach(0..<10, id: \.self) { i in
                VStack(spacing: DS.Spacing.sm) {
                    Text(gainReadout(state.localBands[i]))
                        .font(DS.Typography.micro)
                        .foregroundColor(themeManager.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(minHeight: 12)

                    EQBandFader(gain: state.localBands[i]) { newGain in
                        state.setBand(i, to: newGain)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, DS.Spacing.xs)
                    .accessibilityLabel("Banda de \(frequencyLabel(i)) hercios")

                    Text(frequencyLabel(i))
                        .scaledFont(size: 9, relativeTo: .caption2)
                        .foregroundColor(themeManager.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(minHeight: 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }

    /// Thin left-edge dB scale (+12 / 0 / -12) aligned to the fader track
    /// height. The hidden placeholders mirror the gain readout and
    /// frequency label so the scale lines up with the fader midline.
    private var dbScaleColumn: some View {
        VStack(spacing: DS.Spacing.sm) {
            Text(" ")
                .font(DS.Typography.micro)
                .frame(minHeight: 12)
                .hidden()

            VStack {
                Text("+12")
                Spacer()
                Text("0")
                Spacer()
                Text("-12")
            }
            .font(DS.Typography.micro)
            .foregroundColor(themeManager.textSecondary)
            .frame(maxHeight: .infinity)

            Text(" ")
                .scaledFont(size: 9, relativeTo: .caption2)
                .frame(minHeight: 12)
                .hidden()
        }
        .padding(.trailing, DS.Spacing.xs)
    }

    /// Signed, unit-suffixed readout with a `-0` guard.
    private func gainReadout(_ g: Float) -> String {
        let v = abs(g) < 0.05 ? 0 : g
        // Faders snap to 0.5 dB, so show one decimal for half-steps; keep
        // whole values compact ("+3 dB", not "+3.0 dB").
        return v == v.rounded()
            ? String(format: "%+.0f dB", v)
            : String(format: "%+.1f dB", v)
    }

    private var resetButton: some View {
        let isFlat = state.localBands.allSatisfy { $0 == 0 }
        return Button {
            state.reset()
        } label: {
            Text("Restablecer")
                .font(DS.Typography.captionStrong)
                .foregroundColor(themeManager.tokens.highlightColor)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.sm)
                .glassSurface(in: Capsule(), interactive: true)
        }
        .disabled(isFlat)
        .opacity(isFlat ? 0.4 : 1)
    }

    // MARK: - AutoEQ

    /// Entry point for AutoEQ profiles: opens the searchable headphone catalog
    /// (with file import as its fallback).
    private var autoEQRow: some View {
        Button {
            Haptics.light()
            showAutoEQBrowser = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "waveform.badge.plus")
                    .foregroundColor(themeManager.theme.accentColor)
                Text("Perfil AutoEQ")
                    .font(DS.Typography.captionStrong)
                    .foregroundColor(themeManager.textPrimary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .glassSurface(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityLabel("Elige un perfil AutoEQ para tus auriculares")
    }

    /// Replaces the fader grid while an imported parametric curve is active.
    private func parametricActiveView(_ preset: ParametricEQPreset) -> some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(themeManager.theme.accentColor)
                    Text(preset.name)
                        .font(DS.Typography.titleMedium)
                        .foregroundColor(themeManager.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("\(preset.bands.count) \(preset.bands.count == 1 ? "filtro" : "filtros") · preamplificación \(String(format: "%+.1f", preset.preamp)) dB")
                        .font(DS.Typography.caption)
                        .foregroundColor(themeManager.textSecondary)
                    if preset.bands.count > EQController.bandCount {
                        Text("Se aplican los primeros \(EQController.bandCount) filtros (límite del hardware)")
                            .font(DS.Typography.micro)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, DS.Spacing.lg)

                VStack(spacing: 0) {
                    ForEach(Array(preset.bands.enumerated()), id: \.offset) { index, band in
                        bandRow(band)
                        if index < preset.bands.count - 1 {
                            Divider()
                                .background(themeManager.tokens.hairline)
                                .padding(.leading, DS.Spacing.xxl)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(themeManager.surface)
                )

                savedProfilesSection(active: preset)

                autoEQRow

                Text("Curva paramétrica activa: los deslizadores gráficos y los presets quedan inactivos hasta que la quites.")
                    .font(DS.Typography.micro)
                    .foregroundColor(themeManager.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    Haptics.warning()
                    playerManager.clearParametricEQ()
                } label: {
                    Text("Quitar perfil")
                        .font(DS.Typography.captionStrong)
                        .foregroundColor(.red)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(themeManager.tokens.hairline, lineWidth: 1)
                        )
                }
                .padding(.bottom, DS.Spacing.xl)
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    /// The user's headphone library: tap to switch curves without re-fetching.
    /// `active` is highlighted (and re-tapping it is a no-op).
    @ViewBuilder
    private func savedProfilesSection(active: ParametricEQPreset?) -> some View {
        if !savedProfiles.profiles.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("Tus auriculares")
                    .font(DS.Typography.sectionHeader)
                    .foregroundColor(themeManager.textSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(savedProfiles.profiles) { profile in
                            let isActive = profile.preset == active
                            Button {
                                guard !isActive else { return }
                                Haptics.medium()
                                applyProfile(profile.preset)
                            } label: {
                                HStack(spacing: 6) {
                                    if isActive {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    Text(profile.name)
                                        .font(DS.Typography.captionStrong)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.sm)
                                .background(isActive
                                            ? themeManager.theme.accentColor
                                            : themeManager.surface)
                                .foregroundColor(isActive ? .white : themeManager.textPrimary)
                                .cornerRadius(DS.Radius.lg)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Haptics.warning()
                                    savedProfiles.delete(profile)
                                } label: {
                                    Label("Quitar de Tus auriculares", systemImage: "trash")
                                }
                            }
                            .accessibilityLabel(isActive
                                                ? "\(profile.name), perfil activo"
                                                : "Cambiar a \(profile.name)")
                        }
                    }
                }
            }
        }
    }

    private func bandRow(_ band: ParametricBand) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Text(filterLabel(band.type))
                .font(DS.Typography.micro)
                .fontWeight(.bold)
                .foregroundColor(themeManager.theme.accentColor)
                .frame(width: 28, alignment: .leading)
            Text(frequencyText(band.frequency))
                .font(DS.Typography.caption)
                .foregroundColor(themeManager.textPrimary)
            Spacer()
            Text(String(format: "%+.1f dB", band.gain))
                .font(DS.Typography.caption)
                .foregroundColor(themeManager.textPrimary)
                .monospacedDigit()
            Text(String(format: "Q %.2f", band.q))
                .font(DS.Typography.micro)
                .foregroundColor(themeManager.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func filterLabel(_ type: ParametricFilterType) -> String {
        switch type {
        case .peak: return "PK"
        case .lowShelf: return "LS"
        case .highShelf: return "HS"
        }
    }

    private func frequencyText(_ hz: Float) -> String {
        hz >= 1000
            ? String(format: "%.1f kHz", hz / 1000)
            : String(format: "%.0f Hz", hz)
    }

    private func handleAutoEQImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let name = url.deletingPathExtension().lastPathComponent
            let preset = try AutoEQParser.parse(text, name: name)
            Haptics.medium()
            applyProfile(preset)
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Applies a curve and remembers it, so every profile the user actually
    /// uses lands in their library and switching back later is one tap.
    private func applyProfile(_ preset: ParametricEQPreset) {
        playerManager.applyParametricEQ(preset)
        savedProfiles.remember(preset)
    }

    private func frequencyLabel(_ index: Int) -> String {
        let freq = PlayerManager.eqFrequencies[index]
        if freq >= 1000 { return String(format: "%.0fk", freq / 1000) }
        return String(format: "%.0f", freq)
    }
}

enum EQPreset: String, CaseIterable, Identifiable {
    case flat = "Flat"
    case bassBoost = "Bass Boost"
    case trebleBoost = "Treble Boost"
    case vocal = "Vocal"
    case lounge = "Lounge"
    case rock = "Rock"
    case pop = "Pop"
    case classical = "Classical"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat:        return "Plano"
        case .bassBoost:   return "Realce de graves"
        case .trebleBoost: return "Realce de agudos"
        case .vocal:       return "Voz"
        case .lounge:      return "Lounge"
        case .rock:        return "Rock"
        case .pop:         return "Pop"
        case .classical:   return "Clásica"
        }
    }

    var gains: [Float] {
        switch self {
        case .flat:        return [ 0,  0,  0,  0,  0,  0,  0,  0,  0,  0]
        case .bassBoost:   return [ 6,  5,  3,  0,  0,  0,  0,  0,  0,  0]
        case .trebleBoost: return [ 0,  0,  0,  0,  0,  0,  3,  5,  6,  6]
        case .vocal:       return [-3, -2,  0,  2,  4,  3,  0, -1, -2, -3]
        case .lounge:      return [ 4,  2,  0,  1,  3,  2,  0,  2,  4,  3]
        case .rock:        return [ 4,  2, -1, -2,  0,  2,  4,  3,  2,  1]
        case .pop:         return [ 0,  2,  3,  1, -1, -2,  0,  2,  4,  3]
        case .classical:   return [ 3,  2,  0, -1, -2,  0,  2,  3,  2,  1]
        }
    }
}
