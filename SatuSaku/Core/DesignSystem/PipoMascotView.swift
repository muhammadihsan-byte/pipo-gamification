import RiveRuntime
import SwiftUI

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
    let state: PipoMascotState

    @State private var riveViewModel: RiveViewModel?

    var body: some View {
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

#Preview {
    PipoMascotView(state: .idle)
        .frame(width: 220, height: 220)
}
