import XCTest

final class AegisAppTests: XCTestCase {
  @MainActor
  func testFirstLaunchStartsInOnboardingAndSeedsDefaultWorkspaces() {
    let runtime = makeRuntime(homeDirectoryPath: "/Users/tester")

    XCTAssertEqual(runtime.screen, .onboarding)
    XCTAssertEqual(runtime.protectedWorkspaces.map(\.name), ["OpenClaw", "HermesAgentWorkspace"])
    XCTAssertEqual(
      runtime.protectedWorkspaces.map(\.path),
      [
        "/Users/tester/OpenClaw",
        "/Users/tester/HermesAgentWorkspace",
      ])
    XCTAssertEqual(runtime.defaultTimeoutDecisionKey, "aegis.policy.decision.deny")
  }

  @MainActor
  func testCompletingOnboardingPersistsDashboardRoute() {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)

    let runtime = AppRuntime(
      configuration: .init(
        userDefaults: defaults,
        homeDirectoryURL: URL(fileURLWithPath: "/Users/persisted", isDirectory: true),
        forcedOnboardingCompleted: nil
      )
    )

    runtime.completeOnboarding()

    XCTAssertEqual(runtime.screen, .dashboard)
    XCTAssertTrue(defaults.bool(forKey: AppRuntime.onboardingCompletedKey))

    let reloadedRuntime = AppRuntime(
      configuration: .init(
        userDefaults: defaults,
        homeDirectoryURL: URL(fileURLWithPath: "/Users/persisted", isDirectory: true),
        forcedOnboardingCompleted: nil
      )
    )

    XCTAssertEqual(reloadedRuntime.screen, .dashboard)
  }

  @MainActor
  func testReadinessAggregationKeepsPolicyReadyAndProtectionPending() {
    let runtime = makeRuntime(homeDirectoryPath: "/Users/readiness")

    XCTAssertEqual(runtime.readinessItems.first { $0.kind == .policy }?.indicator.state, .ready)
    XCTAssertEqual(
      runtime.readinessItems.first { $0.kind == .systemExtension }?.indicator.state, .needsAttention
    )
    XCTAssertEqual(
      runtime.readinessItems.first { $0.kind == .loginItem }?.indicator.state, .needsAttention)
    XCTAssertEqual(
      runtime.readinessItems.first { $0.kind == .protectionReadiness }?.indicator.state,
      .needsAttention)
  }

  @MainActor
  func testForcedOnboardingOverrideCanOpenDashboardForUITests() {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)

    let runtime = AppRuntime(
      configuration: .init(
        userDefaults: defaults,
        homeDirectoryURL: URL(fileURLWithPath: "/Users/override", isDirectory: true),
        forcedOnboardingCompleted: true
      )
    )

    XCTAssertEqual(runtime.screen, .dashboard)
  }

  @MainActor
  func testRegisteringLoginItemPersistsReadyState() async throws {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)

    let runtime = AppRuntime(
      configuration: .init(
        userDefaults: defaults,
        homeDirectoryURL: URL(fileURLWithPath: "/Users/login-item", isDirectory: true),
        forcedOnboardingCompleted: true,
        sharedContainerPaths: paths
      )
    )

    await runtime.registerAgentLoginItem()

    XCTAssertTrue(runtime.isAgentLoginItemEnabled)
    XCTAssertEqual(runtime.readinessItems.first { $0.kind == .loginItem }?.indicator.state, .ready)

    let snapshot = try await AegisIPCService(paths: paths).snapshot()
    XCTAssertTrue(snapshot.loginItemEnabled)
  }

  @MainActor
  func testActivatePersistsDefaultPolicyStoreToSharedContainer() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let runtime = makeRuntime(homeDirectoryPath: "/Users/persisted", sharedContainerPaths: paths)

    await runtime.activate()

    let storedPolicyStore = try await LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)
      .load()
    XCTAssertEqual(
      storedPolicyStore.settings.workspaces.map(\.path),
      [
        "/Users/persisted/OpenClaw",
        "/Users/persisted/HermesAgentWorkspace",
      ])
  }

  @MainActor
  func testAddingProtectedWorkspacePersistsNewEntry() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let runtime = makeRuntime(homeDirectoryPath: "/Users/settings", sharedContainerPaths: paths)

    await runtime.activate()
    let initialCount = runtime.protectedWorkspaces.count

    await runtime.addProtectedWorkspace()

    let storedPolicyStore = try await LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)
      .load()
    XCTAssertEqual(runtime.protectedWorkspaces.count, initialCount + 1)
    XCTAssertEqual(storedPolicyStore.settings.workspaces.count, initialCount + 1)
  }

  @MainActor
  func testSavingProtectedWorkspaceNormalizesAndPersistsChanges() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let runtime = makeRuntime(homeDirectoryPath: "/Users/editor", sharedContainerPaths: paths)

    await runtime.activate()
    let workspace = try XCTUnwrap(runtime.protectedWorkspaces.first)

    await runtime.saveProtectedWorkspace(
      id: workspace.id,
      name: "Vault",
      path: "~/Vault/",
      isEnabled: false
    )

    let storedPolicyStore = try await LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)
      .load()
    let updatedWorkspace = try XCTUnwrap(
      storedPolicyStore.settings.workspaces.first(where: { $0.id == workspace.id }))
    XCTAssertEqual(updatedWorkspace.name, "Vault")
    XCTAssertEqual(updatedWorkspace.path, "/Users/editor/Vault")
    XCTAssertFalse(updatedWorkspace.isEnabled)
  }

  @MainActor
  func testChangingDefaultTimeoutDecisionPersistsAndReloadsPolicy() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let runtime = makeRuntime(homeDirectoryPath: "/Users/defaults", sharedContainerPaths: paths)

    await runtime.activate()
    await runtime.setDefaultTimeoutDecision(.allow)

    let storedPolicyStore = try await LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)
      .load()
    let snapshot = try await AegisIPCService(paths: paths).snapshot()
    XCTAssertEqual(runtime.defaultTimeoutDecisionKey, "aegis.policy.decision.allow")
    XCTAssertEqual(storedPolicyStore.settings.defaultTimeoutDecision, .allow)
    XCTAssertNotNil(snapshot.lastPolicyReloadAt)
  }

  @MainActor
  func testClearingRememberedDecisionsPersistsAndReloadsPolicy() async throws {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let fileStore = LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)
    var seededPolicyStore = LocalPolicyStore.defaultStore(
      homeDirectoryURL: URL(fileURLWithPath: "/Users/remembers", isDirectory: true)
    )
    let rememberedWorkspace = try XCTUnwrap(seededPolicyStore.settings.workspaces.first)
    let request = AccessPromptRequest(
      requestID: UUID(),
      eventType: AccessEventType.authOpen,
      targetPath: "/Users/remembers/OpenClaw/spec.txt",
      workspaceID: rememberedWorkspace.id,
      workspaceName: rememberedWorkspace.name,
      processPath: "/Applications/Example.app/Contents/MacOS/Example",
      pid: 7,
      signingIdentifier: "com.nanzhipro.example",
      teamIdentifier: "ABCDE12345",
      isAppleSigned: false,
      deadline: Date().addingTimeInterval(5)
    )
    seededPolicyStore.applyRememberedDecision(
      AccessPromptDecision(
        requestID: request.requestID,
        decision: .deny,
        source: .user,
        rememberChoice: true,
        respondedAt: Date()
      ),
      for: request,
      at: Date()
    )
    try await fileStore.save(seededPolicyStore)

    let runtime = makeRuntime(homeDirectoryPath: "/Users/remembers", sharedContainerPaths: paths)

    await runtime.activate()
    XCTAssertEqual(runtime.rememberedRules.count, 1)

    await runtime.clearRememberedDecisions()

    let storedPolicyStore = try await fileStore.load()
    let snapshot = try await AegisIPCService(paths: paths).snapshot()
    XCTAssertTrue(storedPolicyStore.rememberedRules.isEmpty)
    XCTAssertTrue(runtime.rememberedRules.isEmpty)
    XCTAssertNotNil(snapshot.lastPolicyReloadAt)
  }

  @MainActor
  private func makeRuntime(
    homeDirectoryPath: String,
    sharedContainerPaths: SharedContainerPaths = .temporary(named: UUID().uuidString)
  ) -> AppRuntime {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)

    return AppRuntime(
      configuration: .init(
        userDefaults: defaults,
        homeDirectoryURL: URL(fileURLWithPath: homeDirectoryPath, isDirectory: true),
        forcedOnboardingCompleted: nil,
        sharedContainerPaths: sharedContainerPaths
      )
    )
  }
}
