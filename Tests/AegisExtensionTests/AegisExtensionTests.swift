import XCTest

final class AegisExtensionTests: XCTestCase {
  @MainActor
  func testPromptRequestRoundTripDeliversDecision() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let service = AegisIPCService(paths: paths)
    let agent = AgentRuntime(configuration: .init(sharedContainerPaths: paths))
    let extensionBridge = ExtensionIPCBridge(paths: paths)
    let request = makeRequest(deadlineOffset: 5)

    _ = try await service.publish(endpoint: .app, state: .ready, detail: "app-ready")
    _ = try await service.setLoginItemEnabled(true)
    _ = try await extensionBridge.publishReady()
    await agent.activate()

    _ = try await extensionBridge.enqueuePrompt(request)
    await agent.refresh()
    let currentRequestID = agent.currentRequest?.requestID
    XCTAssertEqual(currentRequestID, request.requestID)

    await agent.allowCurrentPrompt()

    let decision = try await extensionBridge.awaitDecision(for: request)
    XCTAssertEqual(decision.decision, .allow)
    XCTAssertFalse(decision.rememberChoice)
  }

  @MainActor
  func testAwaitDecisionTimesOutWhenAgentDoesNotRespond() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let service = AegisIPCService(paths: paths)
    let extensionBridge = ExtensionIPCBridge(paths: paths)
    let request = makeRequest(deadlineOffset: 0.15)

    _ = try await service.publish(endpoint: .app, state: .ready, detail: "app-ready")
    _ = try await service.setLoginItemEnabled(true)
    _ = try await service.publish(endpoint: .agent, state: .ready, detail: "agent-ready")
    _ = try await extensionBridge.enqueuePrompt(request)

    do {
      _ = try await extensionBridge.awaitDecision(for: request)
      XCTFail("Expected timedOut error")
    } catch let error as IPCTransportError {
      XCTAssertEqual(error, .timedOut)
    }
  }

  @MainActor
  func testSubmittingDecisionForUnknownRequestMapsToRequestNotFound() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let service = AegisIPCService(paths: paths)
    let request = makeRequest(deadlineOffset: 5)
    let decision = AccessPromptDecision(
      requestID: request.requestID,
      decision: .deny,
      source: .user,
      rememberChoice: false,
      respondedAt: Date()
    )

    _ = try await service.publish(endpoint: .app, state: .ready, detail: "app-ready")
    _ = try await service.setLoginItemEnabled(true)
    _ = try await service.publish(endpoint: .agent, state: .ready, detail: "agent-ready")

    do {
      _ = try await service.submitDecision(decision, for: request)
      XCTFail("Expected requestNotFound error")
    } catch let error as IPCTransportError {
      XCTAssertEqual(error, .requestNotFound)
    }
  }

  @MainActor
  func testRememberChoicePersistsRuleToPolicyStore() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let service = AegisIPCService(paths: paths)
    let agent = AgentRuntime(configuration: .init(sharedContainerPaths: paths))
    let extensionBridge = ExtensionIPCBridge(paths: paths)
    let request = makeRequest(deadlineOffset: 5)

    _ = try await service.publish(endpoint: .app, state: .ready, detail: "app-ready")
    _ = try await service.setLoginItemEnabled(true)
    _ = try await extensionBridge.publishReady()
    await agent.activate()

    _ = try await extensionBridge.enqueuePrompt(request)
    await agent.refresh()
    agent.rememberChoice = true
    await agent.denyCurrentPrompt()

    let decision = try await extensionBridge.awaitDecision(for: request)
    XCTAssertTrue(decision.rememberChoice)

    let policyStore = try await LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL).load()
    XCTAssertEqual(policyStore.rememberedRules.count, 1)
    XCTAssertEqual(policyStore.rememberedRules.first?.workspaceID, request.workspaceID)
    XCTAssertEqual(policyStore.rememberedRules.first?.decision, .deny)
  }

  @MainActor
  func testReloadPolicyUpdatesExtensionSnapshot() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let extensionBridge = ExtensionIPCBridge(paths: paths)

    let snapshot = try await extensionBridge.reloadPolicy()

    XCTAssertEqual(snapshot.extensionService.state, .ready)
    XCTAssertNotNil(snapshot.lastPolicyReloadAt)
  }

  @MainActor
  func testDecisionEngineAllowsAppleSignedRequestWithoutPrompt() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    let policyStore = makePolicyStore(homeDirectoryPath: "/Users/tester")
    let engine = try await makeDecisionEngine(
      paths: paths,
      defaultPolicyStore: policyStore,
      transport: transport,
      persistedStore: policyStore
    )
    let request = makeRequest(
      targetPath: "/Users/tester/OpenClaw/spec.txt",
      signingIdentifier: "com.apple.TextEdit",
      teamIdentifier: "APPLE",
      isAppleSigned: true
    )

    let decision = await engine.handleAuthOpen(request)
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .allow)
    XCTAssertEqual(decision.source, .appleSignedDefaultAllow)
    XCTAssertEqual(enqueuedRequestCount, 0)
  }

  @MainActor
  func testDecisionEngineAllowsTrustedAegisProcessWithoutPrompt() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    let policyStore = makePolicyStore(homeDirectoryPath: "/Users/tester")
    let engine = try await makeDecisionEngine(
      paths: paths,
      defaultPolicyStore: policyStore,
      transport: transport,
      persistedStore: policyStore
    )
    let request = makeRequest(signingIdentifier: "com.nanzhipro.AegisAgent")

    let decision = await engine.handleAuthOpen(request)
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .allow)
    XCTAssertEqual(decision.source, .trustedProcessPolicy)
    XCTAssertEqual(enqueuedRequestCount, 0)
  }

  @MainActor
  func testDecisionEngineUsesRememberedRuleBeforePrompt() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    var policyStore = makePolicyStore(homeDirectoryPath: "/Users/tester")
    let rememberedWorkspace = try XCTUnwrap(policyStore.settings.workspaces.first)
    let rememberedRequest = makeRequest(
      workspaceID: rememberedWorkspace.id,
      workspaceName: rememberedWorkspace.name
    )
    policyStore.applyRememberedDecision(
      AccessPromptDecision(
        requestID: rememberedRequest.requestID,
        decision: .deny,
        source: .user,
        rememberChoice: true,
        respondedAt: Date()
      ),
      for: rememberedRequest,
      at: Date()
    )
    let engine = try await makeDecisionEngine(
      paths: paths,
      defaultPolicyStore: policyStore,
      transport: transport,
      persistedStore: policyStore
    )
    let request = makeRequest(workspaceID: UUID(), workspaceName: "ExternalName")

    let decision = await engine.handleAuthOpen(request)
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .deny)
    XCTAssertEqual(decision.source, .rememberedRule)
    XCTAssertEqual(enqueuedRequestCount, 0)
  }

  @MainActor
  func testDecisionEngineAllowsRequestsOutsideProtectedWorkspaces() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    let policyStore = makePolicyStore(homeDirectoryPath: "/Users/tester")
    let engine = try await makeDecisionEngine(
      paths: paths,
      defaultPolicyStore: policyStore,
      transport: transport,
      persistedStore: policyStore
    )
    let request = makeRequest(targetPath: "/Users/tester/Documents/readme.txt")

    let decision = await engine.handleAuthOpen(request)
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .allow)
    XCTAssertEqual(decision.source, .unprotectedPath)
    XCTAssertEqual(enqueuedRequestCount, 0)
  }

  @MainActor
  func testDecisionEngineFallsBackWhenAgentIsUnavailable() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport(enqueueError: .agentUnavailable)
    let policyStore = makePolicyStore(
      homeDirectoryPath: "/Users/tester", defaultTimeoutDecision: .allow)
    let engine = try await makeDecisionEngine(
      paths: paths,
      defaultPolicyStore: policyStore,
      transport: transport,
      persistedStore: policyStore
    )

    let decision = await engine.handleAuthOpen(makeRequest())

    XCTAssertEqual(decision.decision, .allow)
    XCTAssertEqual(decision.source, .agentUnavailable)
  }

  @MainActor
  func testDecisionEngineFallsBackWhenPromptTimesOut() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport(awaitDecisionResult: .failure(.timedOut))
    let policyStore = makePolicyStore(
      homeDirectoryPath: "/Users/tester", defaultTimeoutDecision: .deny)
    let engine = try await makeDecisionEngine(
      paths: paths,
      defaultPolicyStore: policyStore,
      transport: transport,
      persistedStore: policyStore
    )

    let decision = await engine.handleAuthOpen(makeRequest())
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .deny)
    XCTAssertEqual(decision.source, .timeoutFallback)
    XCTAssertEqual(enqueuedRequestCount, 1)
  }

  @MainActor
  func testDecisionEngineFallsBackOnMismatchedAgentResponse() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport(
      awaitDecisionResult: .success(
        AccessPromptDecision(
          requestID: UUID(),
          decision: .allow,
          source: .user,
          rememberChoice: false,
          respondedAt: Date()
        )
      )
    )
    let policyStore = makePolicyStore(
      homeDirectoryPath: "/Users/tester", defaultTimeoutDecision: .deny)
    let engine = try await makeDecisionEngine(
      paths: paths,
      defaultPolicyStore: policyStore,
      transport: transport,
      persistedStore: policyStore
    )

    let decision = await engine.handleAuthOpen(makeRequest())
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .deny)
    XCTAssertEqual(decision.source, .invalidResponse)
    XCTAssertEqual(enqueuedRequestCount, 1)
  }

  @MainActor
  private func makeDecisionEngine(
    paths: SharedContainerPaths,
    defaultPolicyStore: LocalPolicyStore,
    transport: any ExtensionDecisionTransport,
    persistedStore: LocalPolicyStore? = nil
  ) async throws -> ExtensionDecisionEngine {
    let policyStoreFileStore = LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)

    if let persistedStore {
      try await policyStoreFileStore.save(persistedStore)
    }

    return ExtensionDecisionEngine(
      configuration: .init(
        sharedContainerPaths: paths,
        defaultPolicyStore: defaultPolicyStore
      ),
      transport: transport,
      policyStoreFileStore: policyStoreFileStore
    )
  }

  private func makePolicyStore(
    homeDirectoryPath: String,
    defaultTimeoutDecision: AccessDecision = .deny
  ) -> LocalPolicyStore {
    var store = LocalPolicyStore.defaultStore(
      homeDirectoryURL: URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
    )
    store.settings.defaultTimeoutDecision = defaultTimeoutDecision
    return store
  }

  private func makeRequest(
    deadlineOffset: TimeInterval = 5,
    targetPath: String = "/Users/tester/OpenClaw/spec.txt",
    workspaceID: UUID = UUID(),
    workspaceName: String = "OpenClaw",
    processPath: String = "/Applications/Example.app/Contents/MacOS/Example",
    signingIdentifier: String? = "com.nanzhipro.example",
    teamIdentifier: String? = "ABCDE12345",
    isAppleSigned: Bool = false
  ) -> AccessPromptRequest {
    let requestID = UUID()

    return AccessPromptRequest(
      requestID: requestID,
      eventType: AccessEventType.authOpen,
      targetPath: targetPath,
      workspaceID: workspaceID,
      workspaceName: workspaceName,
      processPath: processPath,
      pid: 42,
      signingIdentifier: signingIdentifier,
      teamIdentifier: teamIdentifier,
      isAppleSigned: isAppleSigned,
      deadline: Date().addingTimeInterval(deadlineOffset)
    )
  }
}

private actor MockTransport: ExtensionDecisionTransport {
  private let enqueueError: IPCTransportError?
  private let awaitDecisionResult: Result<AccessPromptDecision, IPCTransportError>?
  private var enqueuedRequests: [AccessPromptRequest] = []

  init(
    enqueueError: IPCTransportError? = nil,
    awaitDecisionResult: Result<AccessPromptDecision, IPCTransportError>? = nil
  ) {
    self.enqueueError = enqueueError
    self.awaitDecisionResult = awaitDecisionResult
  }

  func publishReady(detail: String) async throws -> IPCStatusSnapshot {
    .empty()
  }

  func enqueuePrompt(_ request: AccessPromptRequest) async throws -> IPCStatusSnapshot {
    if let enqueueError {
      throw enqueueError
    }

    enqueuedRequests.append(request)
    return .empty()
  }

  func awaitDecision(for request: AccessPromptRequest) async throws -> AccessPromptDecision {
    if let awaitDecisionResult {
      return try awaitDecisionResult.get()
    }

    return AccessPromptDecision(
      requestID: request.requestID,
      decision: .allow,
      source: .user,
      rememberChoice: false,
      respondedAt: Date()
    )
  }

  func reloadPolicy() async throws -> IPCStatusSnapshot {
    .empty()
  }

  func snapshot() async throws -> IPCStatusSnapshot {
    .empty()
  }

  func enqueuedRequestCount() -> Int {
    enqueuedRequests.count
  }
}
