import SwiftUI
import UniformTypeIdentifiers

struct MissingTrackRepairSheet: View {
    let track: LocalTrack
    let onReimport: (URL) -> Void
    let onRemove: () -> Void
    /// Invoked alongside the SwiftUI `dismiss()` action at every exit
    /// point. The `dismiss` environment value only tears down the
    /// sheet — it does not clear the `@Published` binding that
    /// presented it, so without this callback the sheet can't be
    /// re-opened for the same track after a Cancel/Remove/Re-import.
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var showingImporter = false

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Canción no disponible")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(tokens.textPrimary)

                Text("El archivo '\(track.fileName)' (\(track.fileSizeBytes / 1_000_000) MB) ya no está en el almacenamiento de esta app. Puede ocurrir si borraste los datos de la app o restauraste una copia de seguridad.")
                    .font(.body)
                    .foregroundColor(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Button {
                    showingImporter = true
                } label: {
                    Text("Volver a importar…")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(tokens.accent)
                .accessibilityLabel("Volver a importar el archivo de audio que falta")

                Button(role: .destructive) {
                    onRemove()
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Quitar de la biblioteca")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Quitar de la biblioteca la canción que falta")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    onReimport(url)
                    onDismiss()
                    dismiss()
                }
            }
        }
    }
}
