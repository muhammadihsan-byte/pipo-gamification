import SwiftUI
import WebKit

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
    enum CompanionState { case idle, reassurance, celebration }

    let companion: CompanionState
    var isPresented = true
    var reaction: PipoCompanionReaction = .acknowledge
    var reactionID = 0
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var inViewport = false
    @State private var appeared = false
    @State private var eventID = 0
    @State private var event: PipoCompanionReaction = .acknowledge
    @State private var celebrationID = 0
    @State private var hasEntered = false
    @State private var lastTap: ContinuousClock.Instant?

    private var canPlay: Bool {
        isPresented && appeared && inViewport && scenePhase == .active
    }

    var body: some View {
        Group {
            if companion == .idle {
                Button(action: greetPipo) {
                    livingArtwork.contentShape(Rectangle())
                }
                .buttonStyle(.plain) // The articulated wave is the press response.
                .disabled(!canPlay)
                .accessibilityLabel("Greet Pipo")
                .accessibilityHint(reduceMotion ? "Greet Pipo with gentle feedback." : "Pipo waves hello.")
                .accessibilityValue(reduceMotion ? "Motion reduced" : "Ready to wave")
                .accessibilityIdentifier("pipo.greet")
            } else if companion == .celebration {
                Image(PipoV4Reaction.earnedMilestone.safeBundledStillName)
                    .resizable()
                    .scaledToFit()
                    .phaseAnimator([0, 1, 2, 3, 0], trigger: celebrationID) { content, phase in
                        let moving = canPlay && !reduceMotion
                        content
                            .scaleEffect(moving ? [1.0, 0.98, 1.025, 1.0][phase] : 1)
                            .offset(y: moving ? [0.0, 2.0, -7.0, 1.0][phase] : 0)
                    } animation: { phase in
                        guard canPlay, !reduceMotion else { return nil }
                        switch phase {
                        case 1: return .easeInOut(duration: 0.12)
                        case 2: return .spring(response: 0.28, dampingFraction: 0.78)
                        default: return .spring(response: 0.26, dampingFraction: 0.88)
                        }
                    }
                    .accessibilityLabel("Pipo cheering you on")
            } else {
                livingArtwork.accessibilityLabel("Pipo is here with you")
            }
        }
        .aspectRatio(460.0 / 500.0, contentMode: .fit)
        .onGeometryChange(for: Bool.self) { geometry in
            guard let viewport = geometry.bounds(of: .scrollView) else { return true }
            return viewport.intersects(CGRect(origin: .zero, size: geometry.size))
        } action: { inViewport = $0 }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
        .onChange(of: canPlay) { _, playing in
            guard playing, !hasEntered else { return }
            hasEntered = true
            guard !reduceMotion else { return }
            if companion == .celebration { celebrationID += 1 }
            if companion == .reassurance { respond(.reassure) }
        }
        .onChange(of: reactionID) { _, _ in respond(reaction) }
    }

    private var livingArtwork: some View {
        Group {
            if reduceMotion {
                Image(PipoV4Reaction.resting.safeBundledStillName).resizable().scaledToFit()
            } else {
                IdleArtwork(playing: canPlay, event: event, eventID: eventID)
            }
        }
        .aspectRatio(460.0 / 500.0, contentMode: .fit)
    }

    private func respond(_ reaction: PipoCompanionReaction) {
        guard canPlay, !reduceMotion else { return }
        event = reaction
        eventID += 1
    }

    private func greetPipo() {
        let now = ContinuousClock.now
        guard canPlay,
              lastTap.map({ $0.duration(to: now) >= .milliseconds(1100) }) ?? true else { return }
        lastTap = now
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        onTap?()
        respond(.acknowledge)
    }
}

// One shared V4 renderer for Home, authentication, onboarding and reassurance.
private struct IdleArtwork: UIViewRepresentable {
    let playing: Bool
    let event: PipoCompanionReaction
    let eventID: Int

    func makeUIView(context: Context) -> IdleSurface {
        let surface = IdleSurface()
        surface.lastEventID = eventID
        return surface
    }

    func updateUIView(_ view: IdleSurface, context: Context) {
        view.setPlaying(playing)
        if view.lastEventID != eventID {
            view.lastEventID = eventID
            view.request(event)
        }
    }

    static func dismantleUIView(_ view: IdleSurface, coordinator: ()) {
        view.tearDown()
    }
}

@MainActor
private final class PipoPaintHandler: NSObject, WKScriptMessageHandler {
    weak var surface: IdleSurface?
    init(_ surface: IdleSurface) { self.surface = surface }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        surface?.didPaint(message.webView)
    }
}

private final class IdleSurface: UIView, WKNavigationDelegate {
    private static let document: String? = {
        guard let data = NSDataAsset(name: "PipoV4Idle")?.data,
              let source = String(data: data, encoding: .utf8),
              let start = source.range(of: "<svg"),
              let scriptURL = Bundle.main.url(forResource: "PipoV4Motion", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else { return nil }
        return """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body,svg{width:100%;height:100%;margin:0;overflow:hidden;display:block}</style>
        \(source[start.lowerBound...])
        <script>\(script)</script>
        """
    }()

    private let poster = UIImageView(image: UIImage(named: "PipoV4Neutral"))
    private var artwork: WKWebView?
    private var wantsPlayback = false
    var lastEventID = 0
    private var pending: PipoCompanionReaction?
    private var ready = false
    private var running = false
    private var failed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
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
        if value { failed = false }
        wantsPlayback = value
        syncPlayback()
    }

    func request(_ reaction: PipoCompanionReaction) {
        guard wantsPlayback, window != nil else { return }
        if ready {
            artwork?.evaluateJavaScript("pipoMotion.react('\(reaction.rawValue)')")
        } else {
            pending = reaction
        }
    }

    private func syncPlayback() {
        let shouldPlay = wantsPlayback && window != nil
        if !shouldPlay { pending = nil }
        if shouldPlay, artwork == nil, !failed, let document = Self.document {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(PipoPaintHandler(self), name: "pipoReady")
            let web = WKWebView(frame: bounds, configuration: configuration)
            web.isOpaque = false
            web.backgroundColor = .clear
            web.scrollView.backgroundColor = .clear
            web.scrollView.isScrollEnabled = false
            web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            web.navigationDelegate = self
            web.accessibilityElementsHidden = true
            insertSubview(web, belowSubview: poster)
            artwork = web
            web.loadHTMLString(document, baseURL: nil)
        }
        guard ready, running != shouldPlay else { return }
        running = shouldPlay
        artwork?.evaluateJavaScript(shouldPlay ? "pipoMotion.resume()" : "pipoMotion.pause()")
    }

    func didPaint(_ webView: WKWebView?) {
        guard let webView, webView === artwork, !ready else { return }
        ready = true
        syncPlayback()
        if let pending {
            self.pending = nil
            request(pending)
        }
        // No blank frame while WebKit warms up. The neutral V4 still is always
        // present underneath the fade and is restored after renderer failure.
        UIView.animate(withDuration: 0.16) { self.poster.alpha = 0 }
    }

    func tearDown() {
        wantsPlayback = false
        discardArtwork()
    }

    private func discardArtwork() {
        poster.layer.removeAllAnimations()
        poster.alpha = 1
        artwork?.evaluateJavaScript("window.pipoMotion?.pause()")
        artwork?.stopLoading()
        artwork?.navigationDelegate = nil
        artwork?.configuration.userContentController.removeScriptMessageHandler(forName: "pipoReady")
        artwork?.removeFromSuperview()
        artwork = nil
        pending = nil
        running = false
        ready = false
    }

    private func showFallback() {
        failed = true // Retry on the next visibility cycle, never in a crash loop.
        discardArtwork()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showFallback() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showFallback() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showFallback() }
}

#Preview {
    PipoMascotView(companion: .idle).frame(width: 220, height: 240)
}
