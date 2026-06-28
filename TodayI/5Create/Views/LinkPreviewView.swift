import SwiftUI
import LinkPresentation

struct LinkPreviewView: UIViewRepresentable {
  let url: URL

  func makeUIView(context: Context) -> LPLinkView {
    let view = LPLinkView(url: url)
    let provider = LPMetadataProvider()
    provider.startFetchingMetadata(for: url) { meta, _ in
      if let meta {
        DispatchQueue.main.async { view.metadata = meta }
      }
    }
    return view
  }

  func updateUIView(_ uiView: LPLinkView, context: Context) {}

  // Force LPLinkView to respect the proposed width from SwiftUI layout
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: LPLinkView, context: Context) -> CGSize? {
    let width = proposal.width ?? UIScreen.main.bounds.width
    let height = proposal.height ?? 160
    return CGSize(width: width, height: height)
  }
}
