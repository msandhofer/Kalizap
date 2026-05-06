import AppKit
import SwiftUI
import Kalizap

struct UpdateBannerView: View {
    let state: UpdateState
    let dismissedVersion: String?
    let onDismiss: (String) -> Void
    let strings: BannerStrings

    var body: some View {
        if case .available(let version, let method) = state, dismissedVersion != version {
            VStack(alignment: .leading, spacing: 6) {
                Text(title(for: version))
                    .font(.subheadline)
                    .bold()

                switch method {
                case .homebrewCask(let command):
                    Text(strings.homebrewInstructionLabel)
                        .font(.footnote)
                    HStack(spacing: 4) {
                        Text(command)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            copyToPasteboard(command)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(strings.copyButton)
                    }

                case .directDownload(let url):
                    Text(strings.directDownloadInstructionLabel)
                        .font(.footnote)
                    Text(strings.quarantineHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(strings.openReleaseButton) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }

                HStack {
                    Spacer()
                    Button(strings.laterButton) { onDismiss(version) }
                        .buttonStyle(.borderless)
                        .font(.footnote)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.1))
            )
        }
    }

    private func title(for version: String) -> String {
        strings.titleTemplate.replacingOccurrences(of: "{version}", with: version)
    }

    private func copyToPasteboard(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
