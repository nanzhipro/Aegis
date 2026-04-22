import XCTest

final class AegisExtensionTests: XCTestCase {
  @MainActor
  func testAnonymousXPCListenerLoopbackRoutesPromptDecisionAndStatus() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = AegisExtensionXPCService(listenerMode: .anonymous, paths: paths)
    let endpoint = try XCTUnwrap(transport.listenerEndpoint)
    let appObserver = TestAppObserver()
    let agentObserver = TestAgentObserver()
    let appConnection = makeControlConnection(
      endpoint: endpoint,
      exportedInterface: AegisXPCInterfaces.appObserver(),
      exportedObject: appObserver
    )
    let agentConnection = makeControlConnection(
      endpoint: endpoint,
      exportedInterface: AegisXPCInterfaces.agentPrompt(),
      exportedObject: agentObserver
    )
    let request = makeRequest(deadlineOffset: 5)

    transport.resume()
    defer {
      appConnection.invalidate()
      agentConnection.invalidate()
    }

    _ = try await transport.publishReady(detail: "extension-ready")
    _ = try await publishClientReady(on: appConnection, role: .app)
    let agentSnapshot = try await publishClientReady(on: agentConnection, role: .agent)
    XCTAssertTrue(agentSnapshot.loginItemEnabled)

    _ = try await transport.enqueuePrompt(request)

    let deliveredPrompt = await agentObserver.waitForPrompt(requestID: request.requestID)
    XCTAssertEqual(deliveredPrompt.requestID, request.requestID)

    let busySnapshot = await appObserver.waitForStatus {
      $0.agent.state == .busy && $0.pendingPromptCount == 1
    }
    XCTAssertEqual(busySnapshot.extensionService.state, .busy)

    try await submitDecision(
      on: agentConnection,
      decision: AccessPromptDecision(
        requestID: request.requestID,
        decision: .allow,
        source: .user,
        rememberChoice: false,
        respondedAt: Date()
      )
    )

    let resolvedDecision = try await transport.awaitDecision(for: request)
    XCTAssertEqual(resolvedDecision.decision, .allow)

    let settledSnapshot = await appObserver.waitForStatus {
      $0.pendingPromptCount == 0 && $0.extensionService.state == .ready
    }
    XCTAssertEqual(settledSnapshot.agent.state, .ready)
  }

  @MainActor
  func testAnonymousXPCListenerRequeuesPromptAfterAgentReconnectAndBroadcastsReload() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = AegisExtensionXPCService(listenerMode: .anonymous, paths: paths)
    let endpoint = try XCTUnwrap(transport.listenerEndpoint)
    let appObserver = TestAppObserver()
    let firstAgentObserver = TestAgentObserver()
    let secondAgentObserver = TestAgentObserver()
    let appConnection = makeControlConnection(
      endpoint: endpoint,
      exportedInterface: AegisXPCInterfaces.appObserver(),
      exportedObject: appObserver
    )
    let firstAgentConnection = makeControlConnection(
      endpoint: endpoint,
      exportedInterface: AegisXPCInterfaces.agentPrompt(),
      exportedObject: firstAgentObserver
    )
    let request = makeRequest(deadlineOffset: 5)

    transport.resume()
    defer {
      appConnection.invalidate()
      firstAgentConnection.invalidate()
    }

    _ = try await transport.publishReady(detail: "extension-ready")
    _ = try await publishClientReady(on: appConnection, role: .app)
    _ = try await publishClientReady(on: firstAgentConnection, role: .agent)
    _ = try await transport.enqueuePrompt(request)

    let firstPrompt = await firstAgentObserver.waitForPrompt(requestID: request.requestID)
    XCTAssertEqual(firstPrompt.requestID, request.requestID)

    firstAgentConnection.invalidate()

    let unavailableSnapshot = await appObserver.waitForStatus {
      $0.agent.state == .unavailable && $0.pendingPromptCount == 1
    }
    XCTAssertEqual(unavailableSnapshot.agent.detail, "xpc-invalidated")

    let secondAgentConnection = makeControlConnection(
      endpoint: endpoint,
      exportedInterface: AegisXPCInterfaces.agentPrompt(),
      exportedObject: secondAgentObserver
    )
    defer { secondAgentConnection.invalidate() }

    _ = try await publishClientReady(on: secondAgentConnection, role: .agent)

    let replayedPrompt = await secondAgentObserver.waitForPrompt(requestID: request.requestID)
    XCTAssertEqual(replayedPrompt.requestID, request.requestID)

    _ = try await reloadPolicy(on: appConnection)
    let reloadedSnapshot = await secondAgentObserver.waitForReload()
    XCTAssertNotNil(reloadedSnapshot.lastPolicyReloadAt)
  }

  @MainActor
  func testAnonymousXPCListenerRejectsConnectionsFailingValidation() async throws {
    let transport = AegisExtensionXPCService(
      listenerMode: .anonymous,
      acceptConnection: { _ in false }
    )
    let endpoint = try XCTUnwrap(transport.listenerEndpoint)
    let appObserver = TestAppObserver()
    let appConnection = makeControlConnection(
      endpoint: endpoint,
      exportedInterface: AegisXPCInterfaces.appObserver(),
      exportedObject: appObserver
    )

    transport.resume()
    defer { appConnection.invalidate() }

    do {
      _ = try await publishClientReady(
        on: appConnection,
        role: .app,
        timeoutNanoseconds: 500_000_000
      )
      XCTFail("Expected the rejected connection to fail")
    } catch {
      XCTAssertTrue(true)
    }
  }

  @MainActor
  func testPromptRequestRoundTripDeliversDecision() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let service = AegisIPCService(paths: paths)
    let agent = AgentRuntime(configuration: .init(sharedContainerPaths: paths), service: service)
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
    let agent = AgentRuntime(configuration: .init(sharedContainerPaths: paths), service: service)
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
  func testRuntimeWithFakeEndpointSecurityClientPublishesUnavailableWhenStartFails() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    let (activationCoordinator, _) = try await makeRuntimeWithFakeEndpointSecurityClient(
      paths: paths,
      transport: transport,
      defaultPolicyStore: makePolicyStore(homeDirectoryPath: "/Users/tester"),
      startError: .notPermitted
    )

    do {
      _ = try await activationCoordinator.activate()
      XCTFail("Expected the fake EndpointSecurity client start to fail")
    } catch let error as EndpointSecurityClientError {
      XCTAssertEqual(error, .notPermitted)
    }

    let snapshot = try await transport.snapshot()
    let diagnostic = await transport.lastDiagnostic()

    XCTAssertEqual(snapshot.extensionService.state, .unavailable)
    XCTAssertEqual(snapshot.extensionService.detail, "es-client-not-permitted")
    XCTAssertEqual(diagnostic?.messageKey, "aegis.extension.endpoint-security.not-permitted")
  }

  @MainActor
  func testRuntimeWithFakeEndpointSecurityClientAllowsRequest() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    let (activationCoordinator, fakeClient) = try await makeRuntimeWithFakeEndpointSecurityClient(
      paths: paths,
      transport: transport,
      defaultPolicyStore: makePolicyStore(homeDirectoryPath: "/Users/tester")
    )

    _ = try await activationCoordinator.activate()
    let decision = await fakeClient.handleAuthOpen(makeRequest())

    XCTAssertEqual(decision.decision, .allow)
    XCTAssertEqual(decision.source, .user)
  }

  @MainActor
  func testRuntimeWithFakeEndpointSecurityClientDeniesRequest() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    let (activationCoordinator, fakeClient) = try await makeRuntimeWithFakeEndpointSecurityClient(
      paths: paths,
      transport: transport,
      defaultPolicyStore: makePolicyStore(homeDirectoryPath: "/Users/tester")
    )

    _ = try await activationCoordinator.activate()
    let request = makeRequest()
    await transport.setAwaitDecisionResult(
      .success(
        AccessPromptDecision(
          requestID: request.requestID,
          decision: .deny,
          source: .user,
          rememberChoice: false,
          respondedAt: Date()
        )
      )
    )
    let decision = await fakeClient.handleAuthOpen(request)

    XCTAssertEqual(decision.decision, .deny)
    XCTAssertEqual(decision.source, .user)
  }

  @MainActor
  func testRuntimeWithFakeEndpointSecurityClientTimesOutRequest() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport(awaitDecisionResult: .failure(.timedOut))
    let policyStore = makePolicyStore(
      homeDirectoryPath: "/Users/tester",
      defaultTimeoutDecision: .deny
    )
    let (activationCoordinator, fakeClient) = try await makeRuntimeWithFakeEndpointSecurityClient(
      paths: paths,
      transport: transport,
      defaultPolicyStore: policyStore
    )

    _ = try await activationCoordinator.activate()
    let decision = await fakeClient.handleAuthOpen(makeRequest())

    XCTAssertEqual(decision.decision, .deny)
    XCTAssertEqual(decision.source, .timeoutFallback)
  }

  @MainActor
  func testRuntimeWithFakeEndpointSecurityClientAllowsAppleSignedRequest() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let transport = MockTransport()
    let (activationCoordinator, fakeClient) = try await makeRuntimeWithFakeEndpointSecurityClient(
      paths: paths,
      transport: transport,
      defaultPolicyStore: makePolicyStore(homeDirectoryPath: "/Users/tester")
    )

    _ = try await activationCoordinator.activate()
    let decision = await fakeClient.handleAuthOpen(
      makeRequest(
        targetPath: "/Users/tester/OpenClaw/spec.txt",
        signingIdentifier: "com.apple.TextEdit",
        teamIdentifier: "APPLE",
        isAppleSigned: true
      )
    )
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .allow)
    XCTAssertEqual(decision.source, .appleSignedDefaultAllow)
    XCTAssertEqual(enqueuedRequestCount, 0)
  }

  @MainActor
  func testRuntimeWithFakeEndpointSecurityClientUsesRememberedRule() async throws {
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
    let (activationCoordinator, fakeClient) = try await makeRuntimeWithFakeEndpointSecurityClient(
      paths: paths,
      transport: transport,
      defaultPolicyStore: policyStore,
      persistedStore: policyStore
    )

    _ = try await activationCoordinator.activate()
    let decision = await fakeClient.handleAuthOpen(
      makeRequest(workspaceID: UUID(), workspaceName: "ExternalName")
    )
    let enqueuedRequestCount = await transport.enqueuedRequestCount()

    XCTAssertEqual(decision.decision, .deny)
    XCTAssertEqual(decision.source, .rememberedRule)
    XCTAssertEqual(enqueuedRequestCount, 0)
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

  @MainActor
  private func makeRuntimeWithFakeEndpointSecurityClient(
    paths: SharedContainerPaths,
    transport: MockTransport,
    defaultPolicyStore: LocalPolicyStore,
    persistedStore: LocalPolicyStore? = nil,
    startError: EndpointSecurityClientError? = nil
  ) async throws -> (ExtensionActivationCoordinator, FakeEndpointSecurityClient) {
    let policyStoreFileStore = LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)

    if let persistedStore {
      try await policyStoreFileStore.save(persistedStore)
    }

    let decisionEngine = ExtensionDecisionEngine(
      configuration: .init(
        sharedContainerPaths: paths,
        defaultPolicyStore: defaultPolicyStore
      ),
      transport: transport,
      policyStoreFileStore: policyStoreFileStore
    )
    let authOpenHandler = AuthOpenEventHandler(decisionEngine: decisionEngine)
    let fakeClient = FakeEndpointSecurityClient(
      authOpenHandler: authOpenHandler,
      startError: startError
    )
    let activationCoordinator = ExtensionActivationCoordinator(
      transport: transport,
      authOpenHandler: authOpenHandler,
      endpointSecurityClient: fakeClient
    )

    return (activationCoordinator, fakeClient)
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

private func makeControlConnection(
  endpoint: NSXPCListenerEndpoint,
  exportedInterface: NSXPCInterface,
  exportedObject: Any
) -> NSXPCConnection {
  let connection = NSXPCConnection(listenerEndpoint: endpoint)
  connection.remoteObjectInterface = AegisXPCInterfaces.extensionControl()
  connection.exportedInterface = exportedInterface
  connection.exportedObject = exportedObject
  connection.resume()
  return connection
}

private func publishClientReady(
  on connection: NSXPCConnection,
  role: AegisXPCClientRole,
  timeoutNanoseconds: UInt64 = 2_000_000_000
) async throws -> IPCStatusSnapshot {
  try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<IPCStatusSnapshot, Error>) in
    let continuationBox = ThrowingContinuationBox(continuation)
    let timeoutTask = Task {
      try? await Task.sleep(nanoseconds: timeoutNanoseconds)
      _ = continuationBox.resume(throwing: IPCTransportError.timedOut)
    }

    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        timeoutTask.cancel()
        _ = continuationBox.resume(throwing: error)
      }) as? AegisExtensionControlProtocol
    else {
      timeoutTask.cancel()
      _ = continuationBox.resume(throwing: IPCTransportError.storeFailure)
      return
    }

    proxy.publishClientReady(role: role.rawValue) { snapshot in
      timeoutTask.cancel()
      _ = continuationBox.resume(returning: snapshot)
    }
  }
}

private func reloadPolicy(on connection: NSXPCConnection) async throws -> IPCStatusSnapshot {
  let proxy = try extensionControlProxy(for: connection)

  return try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<IPCStatusSnapshot, Error>) in
    proxy.reloadPolicy { snapshot, error in
      if let error {
        continuation.resume(throwing: error)
      } else if let snapshot {
        continuation.resume(returning: snapshot)
      } else {
        continuation.resume(throwing: IPCTransportError.storeFailure)
      }
    }
  }
}

private func submitDecision(
  on connection: NSXPCConnection,
  decision: AccessPromptDecision
) async throws {
  let proxy = try extensionControlProxy(for: connection)

  try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
    proxy.submitDecision(decision) { error in
      if let error {
        continuation.resume(throwing: error)
      } else {
        continuation.resume(returning: ())
      }
    }
  }
}

private func extensionControlProxy(for connection: NSXPCConnection) throws
  -> AegisExtensionControlProtocol
{
  guard
    let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in })
      as? AegisExtensionControlProtocol
  else {
    throw IPCTransportError.storeFailure
  }

  return proxy
}

private final class TestAppObserver: NSObject, AegisAppObserverProtocol, @unchecked Sendable {
  private let recorder = AppObserverRecorder()

  func statusDidChange(_ snapshot: IPCStatusSnapshot) {
    let recorder = self.recorder
    Task {
      await recorder.record(snapshot)
    }
  }

  func extensionDidEmitDiagnostic(_ event: ExtensionDiagnosticEvent) {
    let recorder = self.recorder
    Task {
      await recorder.record(event)
    }
  }

  func waitForStatus(
    matching predicate: @escaping @Sendable (IPCStatusSnapshot) -> Bool
  ) async -> IPCStatusSnapshot {
    await recorder.waitForStatus(matching: predicate)
  }
}

private final class ThrowingContinuationBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, Error>?

  init(_ continuation: CheckedContinuation<Value, Error>) {
    self.continuation = continuation
  }

  func resume(returning value: Value) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    guard let continuation else {
      return false
    }

    self.continuation = nil
    continuation.resume(returning: value)
    return true
  }

  func resume(throwing error: Error) -> Bool {
    lock.lock()
    defer { lock.unlock() }

    guard let continuation else {
      return false
    }

    self.continuation = nil
    continuation.resume(throwing: error)
    return true
  }
}

private actor AppObserverRecorder {
  private struct StatusWaiter {
    let predicate: @Sendable (IPCStatusSnapshot) -> Bool
    let continuation: CheckedContinuation<IPCStatusSnapshot, Never>
  }

  private var snapshots: [IPCStatusSnapshot] = []
  private var statusWaiters: [StatusWaiter] = []

  func record(_ snapshot: IPCStatusSnapshot) {
    snapshots.append(snapshot)

    if let index = statusWaiters.firstIndex(where: { $0.predicate(snapshot) }) {
      let waiter = statusWaiters.remove(at: index)
      waiter.continuation.resume(returning: snapshot)
    }
  }

  func record(_ event: ExtensionDiagnosticEvent) {}

  func waitForStatus(
    matching predicate: @escaping @Sendable (IPCStatusSnapshot) -> Bool
  ) async -> IPCStatusSnapshot {
    if let existing = snapshots.last(where: predicate) {
      return existing
    }

    return await withCheckedContinuation { continuation in
      statusWaiters.append(StatusWaiter(predicate: predicate, continuation: continuation))
    }
  }
}

private final class TestAgentObserver: NSObject, AegisAgentPromptProtocol, @unchecked Sendable {
  private let recorder = AgentObserverRecorder()

  func presentPrompt(_ request: AccessPromptRequest) {
    let recorder = self.recorder
    Task {
      await recorder.recordPrompt(request)
    }
  }

  func cancelPrompt(requestID: NSUUID) {
    let recorder = self.recorder
    Task {
      await recorder.recordCancelledRequestID(requestID as UUID)
    }
  }

  func policyDidReload(_ snapshot: IPCStatusSnapshot) {
    let recorder = self.recorder
    Task {
      await recorder.recordReload(snapshot)
    }
  }

  func waitForPrompt(requestID: UUID) async -> AccessPromptRequest {
    await recorder.waitForPrompt(requestID: requestID)
  }

  func waitForReload() async -> IPCStatusSnapshot {
    await recorder.waitForReload()
  }
}

private actor AgentObserverRecorder {
  private var prompts: [AccessPromptRequest] = []
  private var reloadSnapshots: [IPCStatusSnapshot] = []
  private var promptWaiters: [UUID: CheckedContinuation<AccessPromptRequest, Never>] = [:]
  private var reloadWaiters: [CheckedContinuation<IPCStatusSnapshot, Never>] = []

  func recordPrompt(_ request: AccessPromptRequest) {
    prompts.append(request)

    if let waiter = promptWaiters.removeValue(forKey: request.requestID) {
      waiter.resume(returning: request)
    }
  }

  func recordCancelledRequestID(_ requestID: UUID) {}

  func recordReload(_ snapshot: IPCStatusSnapshot) {
    reloadSnapshots.append(snapshot)

    if !reloadWaiters.isEmpty {
      let waiter = reloadWaiters.removeFirst()
      waiter.resume(returning: snapshot)
    }
  }

  func waitForPrompt(requestID: UUID) async -> AccessPromptRequest {
    if let existing = prompts.last(where: { $0.requestID == requestID }) {
      return existing
    }

    return await withCheckedContinuation { continuation in
      promptWaiters[requestID] = continuation
    }
  }

  func waitForReload() async -> IPCStatusSnapshot {
    if let existing = reloadSnapshots.last {
      return existing
    }

    return await withCheckedContinuation { continuation in
      reloadWaiters.append(continuation)
    }
  }
}

private actor MockTransport: ExtensionDecisionTransport {
  private let enqueueError: IPCTransportError?
  private var awaitDecisionResult: Result<AccessPromptDecision, IPCTransportError>?
  private var enqueuedRequests: [AccessPromptRequest] = []
  private var statusSnapshot: IPCStatusSnapshot = .empty()
  private var diagnostics: [ExtensionDiagnosticEvent] = []

  init(
    enqueueError: IPCTransportError? = nil,
    awaitDecisionResult: Result<AccessPromptDecision, IPCTransportError>? = nil
  ) {
    self.enqueueError = enqueueError
    self.awaitDecisionResult = awaitDecisionResult
  }

  func startServing() async {}

  func publishReady(detail: String) async throws -> IPCStatusSnapshot {
    try await publishExtensionStatus(state: .ready, detail: detail)
  }

  func publishExtensionStatus(state: IPCServiceState, detail: String) async throws
    -> IPCStatusSnapshot
  {
    statusSnapshot.update(endpoint: .extensionService, state: state, detail: detail, at: Date())
    return statusSnapshot
  }

  func enqueuePrompt(_ request: AccessPromptRequest) async throws -> IPCStatusSnapshot {
    if let enqueueError {
      throw enqueueError
    }

    enqueuedRequests.append(request)
    statusSnapshot.pendingPromptCount = enqueuedRequests.count
    statusSnapshot.update(
      endpoint: .extensionService, state: .busy, detail: "prompt-enqueued", at: Date())
    return statusSnapshot
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
    statusSnapshot.lastPolicyReloadAt = Date()
    statusSnapshot.update(
      endpoint: .extensionService, state: .ready, detail: "policy-reloaded", at: Date())
    return statusSnapshot
  }

  func snapshot() async throws -> IPCStatusSnapshot {
    statusSnapshot
  }

  func emitDiagnostic(_ event: ExtensionDiagnosticEvent) async {
    diagnostics.append(event)
  }

  func enqueuedRequestCount() -> Int {
    enqueuedRequests.count
  }

  func setAwaitDecisionResult(_ result: Result<AccessPromptDecision, IPCTransportError>) {
    awaitDecisionResult = result
  }

  func lastDiagnostic() -> ExtensionDiagnosticEvent? {
    diagnostics.last
  }
}

private actor FakeEndpointSecurityClient: EndpointSecurityClient {
  private let authOpenHandler: AuthOpenEventHandler
  private let startError: EndpointSecurityClientError?
  private var didStart = false

  init(
    authOpenHandler: AuthOpenEventHandler,
    startError: EndpointSecurityClientError? = nil
  ) {
    self.authOpenHandler = authOpenHandler
    self.startError = startError
  }

  func start() async throws {
    if let startError {
      throw startError
    }

    didStart = true
  }

  func stop() async {
    didStart = false
  }

  func handleAuthOpen(_ request: AccessPromptRequest) async -> AccessPromptDecision {
    await authOpenHandler.handle(request)
  }
}
