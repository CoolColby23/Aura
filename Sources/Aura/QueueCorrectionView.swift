import SwiftUI

struct QueueCorrection: Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
}

struct QueueCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State var draft: QueueCorrection
    let save: (QueueCorrection) -> Void

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: BrandMetrics.cardContentSpacing) {
                SymbolTile(symbol: "pencil", tint: theme.primaryColor, size: 40, filled: true)
                VStack(alignment: .leading, spacing: BrandMetrics.titleDetailSpacing) {
                    Text("Correct and Retry")
                        .font(BrandTypography.cardTitle)
                    Text("Last.fm rejected this play. Fix the details below; Aura keeps the original listen time and duplicate protection.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding([.horizontal, .top], BrandMetrics.cardPaddingSpacious)

            Form {
                TextField("Title", text: $draft.title)
                    .accessibilityIdentifier("queue.correction.title")
                TextField("Artist", text: $draft.artist)
                    .accessibilityIdentifier("queue.correction.artist")
                TextField("Album", text: $draft.album, prompt: Text("Optional"))
                    .accessibilityIdentifier("queue.correction.album")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .auraButton()
                    .keyboardShortcut(.cancelAction)
                Button("Save and Retry") { save(draft) }
                    .auraButton(prominent: true)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("queue.correction.save")
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], BrandMetrics.cardPaddingSpacious)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
