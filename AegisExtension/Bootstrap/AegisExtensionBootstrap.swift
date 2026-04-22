import Foundation

public enum AegisExtensionBootstrap {
  public static let targetName = "AegisExtension"

  public struct Runtime: Sendable {
    public let authOpenHandler: AuthOpenEventHandler

    public init(configuration: ExtensionDecisionEngine.Configuration = .live()) {
      let decisionEngine = ExtensionDecisionEngine(configuration: configuration)
      self.authOpenHandler = AuthOpenEventHandler(decisionEngine: decisionEngine)
    }

    public func activate() async throws -> IPCStatusSnapshot {
      try await authOpenHandler.activate()
    }

    public func handleAuthOpen(_ request: AccessPromptRequest) async -> AccessPromptDecision {
      await authOpenHandler.handle(request)
    }
  }

  public static func makeRuntime(configuration: ExtensionDecisionEngine.Configuration = .live())
    -> Runtime
  {
    Runtime(configuration: configuration)
  }
}

@main
enum AegisExtensionMain {
  static func main() {
    let runtime = AegisExtensionBootstrap.makeRuntime()

    Task {
      _ = try? await runtime.activate()
    }

    RunLoop.main.run()
  }
}
