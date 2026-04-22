import Foundation

public enum AegisExtensionBootstrap {
  public static let targetName = "AegisExtension"

  public struct Runtime: Sendable {
    public let authOpenHandler: AuthOpenEventHandler
    private let activationCoordinator: ExtensionActivationCoordinator

    public init(
      configuration: ExtensionDecisionEngine.Configuration = .live(),
      transport: (any ExtensionDecisionTransport)? = nil,
      endpointSecurityClientFactory: ((AuthOpenEventHandler) -> any EndpointSecurityClient)? = nil
    ) {
      let resolvedTransport =
        transport
        ?? AegisExtensionXPCService(
          listenerMode: .machService(name: AegisXPCContract.machServiceName()),
          paths: configuration.sharedContainerPaths,
          codeSigningRequirement: AegisXPCContract.clientCodeSigningRequirement()
        )
      let decisionEngine = ExtensionDecisionEngine(
        configuration: configuration,
        transport: resolvedTransport
      )
      let authOpenHandler = AuthOpenEventHandler(decisionEngine: decisionEngine)
      let endpointSecurityClient =
        endpointSecurityClientFactory?(authOpenHandler)
        ?? LiveEndpointSecurityClient(authOpenHandler: authOpenHandler)

      self.authOpenHandler = authOpenHandler
      self.activationCoordinator = ExtensionActivationCoordinator(
        transport: resolvedTransport,
        authOpenHandler: authOpenHandler,
        endpointSecurityClient: endpointSecurityClient
      )
    }

    public func activate() async throws -> IPCStatusSnapshot {
      try await activationCoordinator.activate()
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
