import RiveRuntime
import SwiftUI
import WebKit

enum PipoMascotState: Equatable, Sendable {
    case idle
    case happy
    case celebrating
    case struggling

    var animationValue: Float {
        switch self {
        case .idle: 0
        case .happy: 1
        case .celebrating: 2
        case .struggling: 3
        }
    }

    var fallbackImageName: String {
        self == .idle ? "PipoAuthHero" : "PipoCelebrating"
    }
}

@MainActor
struct PipoMascotView: View {
    enum CompanionState {
        case idle, tapReaction, reassurance, celebration
    }

    private let state: PipoMascotState
    private let companion: CompanionState?
    private let isPresented: Bool

    init(state: PipoMascotState) {
        self.state = state
        companion = nil
        isPresented = true
    }

    init(companion: CompanionState, isPresented: Bool = true) {
        self.companion = companion
        self.isPresented = isPresented
        state = .idle
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var inViewport = false
    @State private var appeared = false

    @State private var riveViewModel: RiveViewModel?

    var body: some View {
        if let companion {
            Group {
                if companion == .idle && !reduceMotion {
                    IdleArtwork(playing: isPresented && appeared && inViewport && scenePhase == .active)
                } else {
                    Image("PipoV4Neutral").resizable().scaledToFit()
                }
            }
            .aspectRatio(460.0 / 500.0, contentMode: .fit)
            .onGeometryChange(for: Bool.self) { geometry in
                guard let viewport = geometry.bounds(of: .scrollView) else { return true }
                return viewport.intersects(CGRect(origin: .zero, size: geometry.size))
            } action: { visible in
                inViewport = visible
            }
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pipo")
            .accessibilityAddTraits(.isImage)
        } else {
            existingArtwork
        }
    }

    private var existingArtwork: some View {
        Group {
            if let riveViewModel {
                riveViewModel.view()
            } else {
                Image(state.fallbackImageName)
                    .resizable()
                    .scaledToFit()
            }
        }
        .onAppear(perform: loadRiveViewModel)
        .onChange(of: state) { _, newState in
            riveViewModel?.setInput("animState", value: newState.animationValue)
        }
        .accessibilityLabel("Pipo mascot")
    }

    private func loadRiveViewModel() {
        guard riveViewModel == nil else {
            riveViewModel?.setInput("animState", value: state.animationValue)
            return
        }
        guard Bundle.main.url(forResource: "pipo_mascot", withExtension: "riv") != nil else {
            return
        }

        let viewModel = RiveViewModel(
            fileName: "pipo_mascot",
            stateMachineName: "PipoState"
        )
        viewModel.setInput("animState", value: state.animationValue)
        riveViewModel = viewModel
    }
}

// WebKit plays the approved transparent SVG on its own timeline.
private struct IdleArtwork: UIViewRepresentable {
    let playing: Bool

    func makeUIView(context: Context) -> IdleSurface { IdleSurface() }

    func updateUIView(_ view: IdleSurface, context: Context) {
        view.setPlaying(playing)
    }

    static func dismantleUIView(_ view: IdleSurface, coordinator: ()) {
        view.setPlaying(false)
    }
}

private final class IdleSurface: UIView, WKNavigationDelegate {
    private static let document: String? = {
        guard let data = NSDataAsset(name: "PipoV4Idle")?.data,
              let source = String(data: data, encoding: .utf8),
              let start = source.range(of: "<svg") else { return nil }
        return """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body,svg{width:100%;height:100%;margin:0;overflow:hidden;display:block}</style>
        \(source[start.lowerBound...])
        <script>const mascot = document.querySelector('svg'); mascot.pauseAnimations(); mascot.setCurrentTime(0);</script>
        """
    }()

    private let poster = UIImageView(image: UIImage(named: "PipoV4Neutral"))
    private var artwork: WKWebView?
    private var wantsPlayback = false
    private var ready = false
    private var running = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        poster.contentMode = .scaleAspectFit
        poster.frame = bounds
        poster.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(poster)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncPlayback()
    }

    func setPlaying(_ value: Bool) {
        guard wantsPlayback != value else { return }
        wantsPlayback = value
        syncPlayback()
    }

    private func syncPlayback() {
        let shouldPlay = wantsPlayback && window != nil
        if shouldPlay, artwork == nil, let document = Self.document {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let web = WKWebView(frame: bounds, configuration: configuration)
            web.isOpaque = false
            web.backgroundColor = .clear
            web.scrollView.backgroundColor = .clear
            web.scrollView.isScrollEnabled = false
            web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            web.navigationDelegate = self
            insertSubview(web, belowSubview: poster)
            artwork = web
            web.loadHTMLString(document, baseURL: nil)
        }
        guard ready, running != shouldPlay else { return }
        running = shouldPlay
        artwork?.evaluateJavaScript(shouldPlay ? "mascot.unpauseAnimations()" : "mascot.pauseAnimations()")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        syncPlayback()
        poster.isHidden = true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        poster.isHidden = false
        webView.removeFromSuperview()
        artwork = nil
        running = false
        ready = false
    }
}

#Preview {
    PipoMascotView(state: .idle)
        .frame(width: 220, height: 220)
}
