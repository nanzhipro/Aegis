import Foundation
import OSLog

public actor ExtensionDecisionEngine {
  public struct Configuration: Sendable {
    public var sharedContainerPaths: SharedContainerPaths
    public var defaultPolicyStore: LocalPolicyStore
    public var trustedProcessPolicy: TrustedProcessPolicy
    public var now: @Sendable () -> Date

    public init(
      sharedContainerPaths: SharedContainerPaths = .defaultRoot(),
      defaultPolicyStore: LocalPolicyStore = LocalPolicyStore(
        settings: PolicySettings(defaultTimeoutDecision: .deny, workspaces: []),
        rememberedRules: []
      ),
      trustedProcessPolicy: TrustedProcessPolicy = TrustedProcessPolicy(),
      now: @escaping @Sendable () -> Date = { Date() }
    ) {
      self.sharedContainerPaths = sharedContainerPaths
      self.defaultPolicyStore = defaultPolicyStore
      self.trustedProcessPolicy = trustedProcessPolicy
      self.now = now
    }

    public static func live() -> Configuration {
      Configuration()
    }
  }

  private let transport: any ExtensionDecisionTransport
  private let policyStoreFileStore: LocalPolicyStoreFileStore
  private let defaultPolicyStore: LocalPolicyStore
  private let trustedProcessPolicy: TrustedProcessPolicy
  private let now: @Sendable () -> Date
  private let logger = Logger(subsystem: "com.nanzhipro.AegisExtension", category: "DecisionEngine")

  public init(
    configuration: Configuration = .live(),
    transport: (any ExtensionDecisionTransport)? = nil,
    policyStoreFileStore: LocalPolicyStoreFileStore? = nil
  ) {
    let resolvedPolicyStoreFileStore =
      policyStoreFileStore
      ?? LocalPolicyStoreFileStore(fileURL: configuration.sharedContainerPaths.policyStoreURL)

    self.transport =
      transport
      ?? ExtensionIPCBridge(
        paths: configuration.sharedContainerPaths,
        policyStoreFileStore: resolvedPolicyStoreFileStore)
    self.policyStoreFileStore = resolvedPolicyStoreFileStore
    self.defaultPolicyStore = configuration.defaultPolicyStore
    self.trustedProcessPolicy = configuration.trustedProcessPolicy
    self.now = configuration.now
  }

  public func activate() async throws -> IPCStatusSnapshot {
    try await transport.publishReady(detail: "extension-decision-engine-ready")
  }

  public func handleAuthOpen(_ request: AccessPromptRequest) async -> AccessPromptDecision {
    let policyStore = await loadPolicyStore()

    guard let resolvedRequest = resolveProtectedRequest(from: request, using: policyStore) else {
      let decision = allowDecision(for: request, source: .unprotectedPath)
      log(decision: decision, for: request, note: "path-miss")
      return decision
    }

    if resolvedRequest.isAppleSigned {
      let decision = allowDecision(for: resolvedRequest, source: .appleSignedDefaultAllow)
      log(decision: decision, for: resolvedRequest, note: "apple-signed")
      return decision
    }

    if trustedProcessPolicy.matches(resolvedRequest) {
      let decision = allowDecision(for: resolvedRequest, source: .trustedProcessPolicy)
      log(decision: decision, for: resolvedRequest, note: "trusted-process")
      return decision
    }

    if let rememberedRule = policyStore.rememberedDecision(for: resolvedRequest) {
      let decision = AccessPromptDecision(
        requestID: resolvedRequest.requestID,
        decision: rememberedRule.decision,
        source: .rememberedRule,
        rememberChoice: false,
        respondedAt: now()
      )
      log(decision: decision, for: resolvedRequest, note: "remembered-rule")
      return decision
    }

    return await promptForDecision(for: resolvedRequest, using: policyStore)
  }

  private func loadPolicyStore() async -> LocalPolicyStore {
    do {
      return try await policyStoreFileStore.load(defaultingTo: defaultPolicyStore)
    } catch {
      logger.error("Falling back to the in-memory default policy store after a load failure.")
      return defaultPolicyStore
    }
  }

  private func resolveProtectedRequest(
    from request: AccessPromptRequest,
    using policyStore: LocalPolicyStore
  ) -> AccessPromptRequest? {
    let enabledWorkspaces = policyStore.settings.workspaces.filter(\.isEnabled)

    guard !enabledWorkspaces.isEmpty else {
      return request
    }

    let normalizer = PathNormalizer()
    let matchedWorkspace =
      enabledWorkspaces.last(where: {
        $0.id == request.workspaceID
          && $0.matches(targetPath: request.targetPath, using: normalizer)
      })
      ?? enabledWorkspaces.last(where: {
        $0.matches(targetPath: request.targetPath, using: normalizer)
      })

    guard let matchedWorkspace else {
      return nil
    }

    return AccessPromptRequest(
      requestID: request.requestID,
      eventType: request.eventType,
      targetPath: request.targetPath,
      workspaceID: matchedWorkspace.id,
      workspaceName: matchedWorkspace.name,
      processPath: request.processPath,
      pid: request.pid,
      signingIdentifier: request.signingIdentifier,
      teamIdentifier: request.teamIdentifier,
      isAppleSigned: request.isAppleSigned,
      deadline: request.deadline
    )
  }

  private func promptForDecision(
    for request: AccessPromptRequest,
    using policyStore: LocalPolicyStore
  ) async -> AccessPromptDecision {
    do {
      _ = try await transport.enqueuePrompt(request)
      let decision = try await transport.awaitDecision(for: request)

      guard decision.requestID == request.requestID else {
        let fallback = fallbackDecision(
          for: request,
          decision: policyStore.settings.defaultTimeoutDecision,
          source: .invalidResponse
        )
        log(decision: fallback, for: request, note: "mismatched-response")
        return fallback
      }

      log(decision: decision, for: request, note: "agent-response")
      return decision
    } catch let error as IPCTransportError {
      let source: DecisionSource

      switch error {
      case .timedOut:
        source = .timeoutFallback
      case .agentUnavailable:
        source = .agentUnavailable
      case .invalidResponse, .requestNotFound, .storeFailure:
        source = .invalidResponse
      }

      let fallback = fallbackDecision(
        for: request,
        decision: policyStore.settings.defaultTimeoutDecision,
        source: source
      )
      log(decision: fallback, for: request, note: error.rawValue)
      return fallback
    } catch {
      let fallback = fallbackDecision(
        for: request,
        decision: policyStore.settings.defaultTimeoutDecision,
        source: .invalidResponse
      )
      log(decision: fallback, for: request, note: "unexpected-error")
      return fallback
    }
  }

  private func allowDecision(
    for request: AccessPromptRequest,
    source: DecisionSource
  ) -> AccessPromptDecision {
    AccessPromptDecision(
      requestID: request.requestID,
      decision: .allow,
      source: source,
      rememberChoice: false,
      respondedAt: now()
    )
  }

  private func fallbackDecision(
    for request: AccessPromptRequest,
    decision: AccessDecision,
    source: DecisionSource
  ) -> AccessPromptDecision {
    AccessPromptDecision(
      requestID: request.requestID,
      decision: decision,
      source: source,
      rememberChoice: false,
      respondedAt: now()
    )
  }

  private func log(
    decision: AccessPromptDecision,
    for request: AccessPromptRequest,
    note: String
  ) {
    logger.log(
      "AUTH_OPEN note=\(note, privacy: .public) source=\(decision.source.rawValue, privacy: .public) decision=\(decision.decision.rawValue, privacy: .public) requestID=\(request.requestID.uuidString, privacy: .public) path=\(request.targetPath, privacy: .private) process=\(request.processPath, privacy: .private)"
    )
  }
}
