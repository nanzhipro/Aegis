import XCTest

final class AegisSharedTests: XCTestCase {
  func testDefaultPolicyStoreBuildsExpectedFallbackAndWorkspaces() {
    let homeURL = URL(fileURLWithPath: "/tmp/aegis-home", isDirectory: true)

    let store = LocalPolicyStore.defaultStore(homeDirectoryURL: homeURL)

    XCTAssertEqual(store.settings.defaultTimeoutDecision, .deny)
    XCTAssertEqual(store.settings.workspaces.map(\.name), ["OpenClaw", "HermesAgentWorkspace"])
    XCTAssertEqual(
      store.settings.workspaces.map(\.path),
      [
        "/tmp/aegis-home/OpenClaw",
        "/tmp/aegis-home/HermesAgentWorkspace",
      ])
    XCTAssertTrue(store.settings.workspaces.allSatisfy(\.isEnabled))
    XCTAssertTrue(store.rememberedRules.isEmpty)
  }

  func testPathNormalizerExpandsTildeResolvesSymlinkAndRemovesTrailingSlash() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let homeURL = tempDirectory.appendingPathComponent("home", isDirectory: true)
    let workspaceURL = homeURL.appendingPathComponent("OpenClaw", isDirectory: true)
    let symlinkURL = homeURL.appendingPathComponent("Shortcut")

    try FileManager.default.createDirectory(
      at: workspaceURL, withIntermediateDirectories: true, attributes: nil)
    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: workspaceURL)

    let normalizer = PathNormalizer(homeDirectoryURL: homeURL)

    XCTAssertEqual(normalizer.normalize("~/Shortcut/"), workspaceURL.path)
  }

  func testProtectedWorkspaceMatchesExactPathAndDescendantPaths() {
    let normalizer = PathNormalizer(
      homeDirectoryURL: URL(fileURLWithPath: "/Users/test", isDirectory: true))
    let workspace = ProtectedWorkspace(
      id: UUID(),
      name: "Workspace",
      path: "~/Projects/Workspace/",
      isEnabled: true
    )

    XCTAssertTrue(workspace.matches(targetPath: "~/Projects/Workspace", using: normalizer))
    XCTAssertTrue(
      workspace.matches(targetPath: "~/Projects/Workspace/src/main.swift", using: normalizer))
    XCTAssertFalse(
      workspace.matches(targetPath: "~/Projects/Workspace-Other/file.txt", using: normalizer))
  }

  func testAccessPromptContractsRoundTripThroughCodec() throws {
    let request = makeRequest()
    let decision = AccessPromptDecision(
      requestID: request.requestID,
      decision: .allow,
      source: .user,
      rememberChoice: true,
      respondedAt: Date(timeIntervalSince1970: 2_000)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let requestCopy = try decoder.decode(AccessPromptRequest.self, from: encoder.encode(request))
    let decisionCopy = try decoder.decode(AccessPromptDecision.self, from: encoder.encode(decision))

    XCTAssertEqual(requestCopy, request)
    XCTAssertEqual(decisionCopy, decision)
  }

  func testRememberedDecisionMatchesOnlyExactGranularity() {
    let request = makeRequest()
    let matchingRule = RememberedDecisionRule(
      id: UUID(),
      workspaceID: request.workspaceID,
      process: .from(request: request),
      decision: .allow,
      createdAt: Date(timeIntervalSince1970: 10),
      updatedAt: Date(timeIntervalSince1970: 10)
    )
    let mismatchedWorkspace = AccessPromptRequest(
      requestID: request.requestID,
      eventType: request.eventType,
      targetPath: request.targetPath,
      workspaceID: UUID(),
      workspaceName: request.workspaceName,
      processPath: request.processPath,
      pid: request.pid,
      signingIdentifier: request.signingIdentifier,
      teamIdentifier: request.teamIdentifier,
      isAppleSigned: request.isAppleSigned,
      deadline: request.deadline
    )

    XCTAssertTrue(matchingRule.matches(request: request))
    XCTAssertFalse(matchingRule.matches(request: mismatchedWorkspace))
  }

  func testRememberedDecisionSkipsAppleSignedRequests() {
    let request = AccessPromptRequest(
      requestID: UUID(),
      eventType: AccessEventType.authOpen,
      targetPath: "/tmp/workspace/file.txt",
      workspaceID: UUID(),
      workspaceName: "Workspace",
      processPath: "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit",
      pid: 42,
      signingIdentifier: "com.apple.TextEdit",
      teamIdentifier: "APPLE",
      isAppleSigned: true,
      deadline: Date(timeIntervalSince1970: 3_000)
    )

    var store = LocalPolicyStore.defaultStore(
      homeDirectoryURL: URL(fileURLWithPath: "/Users/test", isDirectory: true))
    store.applyRememberedDecision(
      AccessPromptDecision(
        requestID: request.requestID,
        decision: .allow,
        source: .user,
        rememberChoice: true,
        respondedAt: Date(timeIntervalSince1970: 3_001)
      ),
      for: request,
      at: Date(timeIntervalSince1970: 3_001)
    )

    XCTAssertNil(store.rememberedDecision(for: request))
    XCTAssertTrue(store.rememberedRules.isEmpty)
  }

  func testRememberedDecisionUpsertsExistingRule() {
    let request = makeRequest()
    var store = LocalPolicyStore.defaultStore(
      homeDirectoryURL: URL(fileURLWithPath: "/Users/test", isDirectory: true))

    store.applyRememberedDecision(
      AccessPromptDecision(
        requestID: request.requestID,
        decision: .allow,
        source: .user,
        rememberChoice: true,
        respondedAt: Date(timeIntervalSince1970: 1_001)
      ),
      for: request,
      at: Date(timeIntervalSince1970: 1_001)
    )
    store.applyRememberedDecision(
      AccessPromptDecision(
        requestID: request.requestID,
        decision: .deny,
        source: .user,
        rememberChoice: true,
        respondedAt: Date(timeIntervalSince1970: 1_002)
      ),
      for: request,
      at: Date(timeIntervalSince1970: 1_002)
    )

    XCTAssertEqual(store.rememberedRules.count, 1)
    XCTAssertEqual(store.rememberedRules[0].decision, .deny)
    XCTAssertEqual(store.rememberedRules[0].createdAt, Date(timeIntervalSince1970: 1_001))
    XCTAssertEqual(store.rememberedRules[0].updatedAt, Date(timeIntervalSince1970: 1_002))
  }

  func testLocalPolicyStoreCodecAndFileStoreRoundTrip() async throws {
    let tempDirectory = try makeTemporaryDirectory()
    let fileURL = tempDirectory.appendingPathComponent(
      SharedPolicyDefaults.localPolicyStoreFileName)
    let fileStore = LocalPolicyStoreFileStore(fileURL: fileURL)

    var expected = LocalPolicyStore.defaultStore(homeDirectoryURL: tempDirectory)
    expected.settings.defaultTimeoutDecision = .allow
    expected.clearRememberedDecisions()
    expected.applyRememberedDecision(
      AccessPromptDecision(
        requestID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        decision: .deny,
        source: .timeoutFallback,
        rememberChoice: true,
        respondedAt: Date(timeIntervalSince1970: 2_500)
      ),
      for: makeRequest(),
      at: Date(timeIntervalSince1970: 2_500)
    )

    try await fileStore.save(expected)
    let loaded = try await fileStore.load()

    XCTAssertEqual(loaded, expected)
  }

  func testComponentStatusRoundTrips() throws {
    let status = ComponentStatus(
      systemExtension: .init(state: .ready),
      loginItem: .init(state: .needsAttention, detail: "Needs approval"),
      policy: .init(state: .ready),
      protectionReadiness: .init(state: .unavailable, detail: "Full Disk Access missing")
    )

    let data = try JSONEncoder().encode(status)
    let decoded = try JSONDecoder().decode(ComponentStatus.self, from: data)

    XCTAssertEqual(decoded, status)
  }

  private func makeRequest() -> AccessPromptRequest {
    AccessPromptRequest(
      requestID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
      eventType: AccessEventType.authOpen,
      targetPath: "/tmp/workspace/file.txt",
      workspaceID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
      workspaceName: "Workspace",
      processPath: "/usr/local/bin/tool",
      pid: 1_234,
      signingIdentifier: "com.example.tool",
      teamIdentifier: "TEAM123456",
      isAppleSigned: false,
      deadline: Date(timeIntervalSince1970: 2_000)
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: nil)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }
    return directory
  }
}
