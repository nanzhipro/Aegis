import Foundation

public struct AuthOpenEventHandler: Sendable {
  private let decisionEngine: ExtensionDecisionEngine

  public init(decisionEngine: ExtensionDecisionEngine) {
    self.decisionEngine = decisionEngine
  }

  public func activate() async throws -> IPCStatusSnapshot {
    try await decisionEngine.activate()
  }

  public func handle(_ request: AccessPromptRequest) async -> AccessPromptDecision {
    await decisionEngine.handleAuthOpen(request)
  }
}
