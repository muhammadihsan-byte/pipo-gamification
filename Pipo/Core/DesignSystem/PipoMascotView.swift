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

// #71: Canonical Figma Performance Kit V1.3 pose identifiers. A source pose
// is NOT a runtime image until a verified export is included in the bundle.
// Never substitute archived side/rear studies for these approved front poses.
enum PipoV4ApprovedPose: String, CaseIterable, Sendable {
    case idle = "1527:7055"
    case sparkNoticed = "1527:7189"
    case curiousLean = "1527:7323"
    case reachSpark = "1527:7457"
    case hugSpark = "1527:7591"
    case presentSpark = "1527:7725"
    case miniJump = "1527:7859"
    case handsUp = "1527:7993"
    case proudBest = "1527:8127"
    case gentleRecovery = "1527:8261"
    case calmRest = "1527:8395"
    case hopefulLookUp = "1527:8529"

    // Only images confirmed in the existing native bundle may be referenced.
    // Remaining source poses require independent, licensed Figma exports and
    // native size/visual QA before being mapped to asset names.
    var bundledStillName: String? {
        switch self {
        case .idle: "PipoV4Neutral"
        case .handsUp: "PipoV4Joy" // contextual celebration still; not an exact pose export
        default: nil
        }
    }
}

/// Presentation only. Caller must supply an authenticated, persisted event;
/// this mapping never infers a reward or awards XP from a visual state.
enum PipoV4Reaction: Sendable {
    case resting
    case noticedFirstEligiblePeriod
    case earnedMilestone
    case supportiveRecovery

    var approvedPose: PipoV4ApprovedPose {
        switch self {
        case .resting: .idle
        case .noticedFirstEligiblePeriod: .sparkNoticed
        case .earnedMilestone: .handsUp
        case .supportiveRecovery: .gentleRecovery
        }
    }

    var safeBundledStillName: String {
        approvedPose.bundledStillName ?? "PipoV4Neutral"
    }
}

@MainActor
struct PipoMascotView: View {
    enum CompanionState {
        case idle, reassurance, celebration
    }

    private let state: PipoMascotState
    private let companion: CompanionState?
    private let isPresented: Bool
    private let onTap: (() -> Void)?

    init(state: PipoMascotState) {
        self.state = state
        companion = nil
        isPresented = true
        onTap = nil
    }

    init(companion: CompanionState, isPresented: Bool = true, onTap: (() -> Void)? = nil) {
        self.companion = companion
        self.isPresented = isPresented
        self.onTap = onTap
        state = .idle
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var inViewport = false
    @State private var appeared = false
    @State private var tapID = 0
    @State private var didPresentJoy = false
    @State private var lastTap: ContinuousClock.Instant?

    private var canPlay: Bool {
        isPresented && appeared && inViewport && scenePhase == .active
    }

    @State private var riveViewModel: RiveViewModel?

    var body: some View {
        if let companion {
            Group {
                if companion == .idle {
                    Button(action: greetPipo) {
                        Group {
                            if reduceMotion {
                                neutralStill
                            } else {
                                IdleArtwork(playing: canPlay, tapID: tapID)
                            }
                        }
                        .aspectRatio(460.0 / 500.0, contentMode: .fit)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPlay)
                    .accessibilityLabel("Greet Pipo")
                    .accessibilityIdentifier("pipo.greet")
                } else if companion == .celebration {
                    Image(PipoV4Reaction.earnedMilestone.safeBundledStillName)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(reduceMotion ? 1 : (didPresentJoy ? 1 : 0.94))
                        .onAppear {
                            guard !reduceMotion else { return }
                            didPresentJoy = false
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                didPresentJoy = true
                            }
                        }
                        .accessibilityLabel("Pipo celebrating a recorded saving")
                } else {
                    neutralStill.accessibilityLabel("Pipo")
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
        } else {
            existingArtwork
        }
    }

    private var neutralStill: some View {
        Image(PipoV4Reaction.resting.safeBundledStillName).resizable().scaledToFit()
    }

    // A tap is a one-shot event layered over the current idle pose.
    private func greetPipo() {
        let now = ContinuousClock.now
        guard canPlay, lastTap.map({ $0.duration(to: now) >= .milliseconds(900) }) ?? true else { return }
        lastTap = now
        onTap?()
        if reduceMotion {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            tapID += 1
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

    let tapID: Int

    func makeUIView(context: Context) -> IdleSurface {
        let surface = IdleSurface()
        surface.lastTapID = tapID
        return surface
    }

    func updateUIView(_ view: IdleSurface, context: Context) {
        view.setPlaying(playing)
        if view.lastTapID != tapID {
            view.lastTapID = tapID
            view.requestTap()
        }
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
        <script>
        const mascot = document.querySelector('svg');
        mascot.pauseAnimations();
        mascot.setCurrentTime(0);

        // Independent outer groups compose with the approved idle transforms.
        function tapTrack(selector, values) {
            const part = mascot.querySelector(selector);
            const group = document.createElementNS(mascot.namespaceURI, 'g');
            part.parentNode.insertBefore(group, part);
            group.appendChild(part);
            const track = document.createElementNS(mascot.namespaceURI, 'animateTransform');
            Object.entries({
                attributeName: 'transform', type: 'rotate', begin: 'indefinite', dur: '0.9s',
                keyTimes: '0;0.16;0.42;0.62;1', values: values, calcMode: 'spline',
                keySplines: '0.3 0 0.6 1;0.2 0 0.3 1;0.35 0 0.65 1;0.4 0 0.6 1'
            }).forEach(([key, value]) => track.setAttribute(key, value));
            group.appendChild(track);
            return track;
        }
        const tapTracks = [
            tapTrack('#UpperBody', '0 162 248;-0.8 162 248;2.0 162 248;1.8 162 248;0 162 248'),
            tapTrack('[aria-label="Arm_L"]', '0 99 191;-3 99 191;22 99 191;17 99 191;0 99 191'),
            tapTrack('[aria-label="Ear_L"]', '0 145 89;0 145 89;-4 145 89;-2 145 89;0 145 89'),
            tapTrack('[aria-label="FlowerRoot"]', '0 192 84;0 192 84;-1.5 192 84;-3 192 84;0 192 84')
        ];
        let tapEnd = 0;
        function acknowledgeTap() {
            const now = mascot.getCurrentTime();
            if (mascot.animationsPaused() || now < tapEnd) return;
            tapEnd = now + 0.9;
            tapTracks.forEach(track => track.beginElement());
        }
        function pausePipo() {
            if (mascot.getCurrentTime() < tapEnd) tapTracks.forEach(track => track.endElement());
            tapEnd = 0;
            mascot.pauseAnimations();
        }
        </script>
        """
    }()

    private let poster = UIImageView(image: UIImage(named: "PipoV4Neutral"))
    private var artwork: WKWebView?
    private var wantsPlayback = false
    var lastTapID = 0
    private var pendingTap = false
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

    func requestTap() {
        guard wantsPlayback, window != nil else { return }
        if ready {
            artwork?.evaluateJavaScript("acknowledgeTap()")
        } else {
            pendingTap = true
        }
    }

    private func syncPlayback() {
        let shouldPlay = wantsPlayback && window != nil
        if !shouldPlay { pendingTap = false }
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
        artwork?.evaluateJavaScript(shouldPlay ? "mascot.unpauseAnimations()" : "pausePipo()")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        syncPlayback()
        if pendingTap {
            pendingTap = false
            requestTap()
        }
        poster.isHidden = true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        poster.isHidden = false
        webView.removeFromSuperview()
        artwork = nil
        pendingTap = false
        running = false
        ready = false
    }
}

#Preview {
    PipoMascotView(state: .idle)
        .frame(width: 220, height: 220)
}
