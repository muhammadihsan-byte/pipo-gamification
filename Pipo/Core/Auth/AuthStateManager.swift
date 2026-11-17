import Foundation
import Observation

enum AuthState: Equatable, Sendable {
    case unauthenticated
    case authenticated
}

@MainActor
@Observable
final class AuthStateManager {
    private(set) var authState: AuthState
    private(set) var userID: UUID?

    init(initialState: AuthState = .unauthenticated, userID: UUID? = nil) {
        authState = initialState
        self.userID = userID
    }

    func signIn(userID: UUID? = nil) {
        authState = .authenticated
        self.userID = userID
    }

    func signOut() {
        authState = .unauthenticated
        userID = nil
    }
}
