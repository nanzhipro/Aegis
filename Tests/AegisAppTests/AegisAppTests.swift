import XCTest

final class AegisAppTests: XCTestCase {
  private final class FakeAgentLoginItemRegistrar: @unchecked Sendable {
    var state: AppRuntime.AgentLoginItemRegistrationState
    var registerCallCount = 0
    var unregisterCallCount = 0

    init(initialState: AppRuntime.AgentLoginItemRegistrationState = .notRegistered) {
      self.state = initialState
    }

    func status() -> AppRuntime.AgentLoginItemRegistrationState {
      state
    }

    func register() {
      registerCallCount += 1
      state = .enabled
    }

    func unregister() {
      unregisterCallCount += 1
      state = .notRegistered
    }
  }

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
    let registrar = FakeAgentLoginItemRegistrar()

    let runtime = AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: "/Users/persisted",
        forcedOnboardingCompleted: nil,
        agentLoginItemRegistrar: registrar
      )
    )

    runtime.completeOnboarding()

    XCTAssertEqual(runtime.screen, .dashboard)
    XCTAssertTrue(defaults.bool(forKey: AppRuntime.onboardingCompletedKey))

    let reloadedRuntime = AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: "/Users/persisted",
        forcedOnboardingCompleted: nil,
        agentLoginItemRegistrar: registrar
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
    let registrar = FakeAgentLoginItemRegistrar()

    let runtime = AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: "/Users/override",
        forcedOnboardingCompleted: true,
        agentLoginItemRegistrar: registrar
      )
    )

    XCTAssertEqual(runtime.screen, .dashboard)
  }

  @MainActor
  func testMenuActionKeysMatchPhaseTwoContract() {
    let runtime = makeRuntime(homeDirectoryPath: "/Users/menu")

    XCTAssertEqual(runtime.openOnboardingActionKey, "aegis.menu.open_onboarding")
    XCTAssertEqual(runtime.systemExtensionInstallActionKey, "aegis.menu.install_extension")

    runtime.overrideSystemExtensionInstallationStateForTesting(.requesting)
    XCTAssertEqual(runtime.systemExtensionInstallActionKey, "aegis.menu.install_extension.pending")

    runtime.overrideSystemExtensionInstallationStateForTesting(.willCompleteAfterReboot)
    XCTAssertEqual(runtime.systemExtensionInstallActionKey, "aegis.menu.install_extension.reboot")

    runtime.overrideSystemExtensionInstallationStateForTesting(.activated)
    XCTAssertEqual(runtime.systemExtensionInstallActionKey, "aegis.menu.reinstall_extension")
  }

  @MainActor
  func testInstallSystemExtensionFocusesPermissionsStepDuringOnboarding() {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let registrar = FakeAgentLoginItemRegistrar()

    let runtime = AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: "/Users/install-onboarding",
        forcedOnboardingCompleted: false,
        isUITesting: true,
        agentLoginItemRegistrar: registrar
      )
    )

    runtime.selectedOnboardingStep = .welcome
    runtime.installSystemExtension()

    XCTAssertEqual(runtime.selectedOnboardingStep, .permissions)
  }

  @MainActor
  func testInstallSystemExtensionFocusesOverviewWhenOnboardingIsComplete() {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let registrar = FakeAgentLoginItemRegistrar()

    let runtime = AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: "/Users/install-dashboard",
        forcedOnboardingCompleted: true,
        isUITesting: true,
        agentLoginItemRegistrar: registrar
      )
    )

    runtime.selectedSidebarItem = .protectedFolders
    runtime.installSystemExtension()

    XCTAssertEqual(runtime.selectedSidebarItem, .overview)
  }

  @MainActor
  func testSystemExtensionInstallationStatusTextTracksProgressAndFailureReason() {
    let runtime = makeRuntime(homeDirectoryPath: "/Users/install-status")

    XCTAssertEqual(
      runtime.systemExtensionInstallationStatusText,
      String(localized: "aegis.readiness.system_extension.detail")
    )
    XCTAssertNil(runtime.systemExtensionInstallationFailureReason)

    runtime.overrideSystemExtensionInstallationStateForTesting(.awaitingUserApproval)
    XCTAssertEqual(
      runtime.systemExtensionInstallationStatusText,
      String(localized: "aegis.menu.install_extension.pending")
    )
    XCTAssertEqual(runtime.systemExtensionInstallationFeedbackState, .needsAttention)

    runtime.overrideSystemExtensionInstallationStateForTesting(.failed(reason: "sysextd denied"))
    XCTAssertEqual(
      runtime.systemExtensionInstallationStatusText,
      String(localized: "aegis.readiness.system_extension.detail")
    )
    XCTAssertEqual(runtime.systemExtensionInstallationFailureReason, "sysextd denied")
    XCTAssertEqual(runtime.systemExtensionInstallationFeedbackState, .needsAttention)
  }

  @MainActor
  func testRegisteringLoginItemPersistsReadyState() async throws {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let registrar = FakeAgentLoginItemRegistrar()

    let runtime = AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: "/Users/login-item",
        forcedOnboardingCompleted: true,
        sharedContainerPaths: paths,
        agentLoginItemRegistrar: registrar
      )
    )

    await runtime.registerAgentLoginItem()

    XCTAssertTrue(runtime.isAgentLoginItemEnabled)
    XCTAssertEqual(registrar.registerCallCount, 1)
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
  func testRemovingProtectedWorkspaceClearsMatchingRememberedDecisionsAndReloadsPolicy()
    async throws
  {
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let fileStore = LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)
    var seededPolicyStore = LocalPolicyStore.defaultStore(
      homeDirectoryURL: URL(fileURLWithPath: "/Users/removal", isDirectory: true)
    )
    let removedWorkspace = try XCTUnwrap(seededPolicyStore.settings.workspaces.first)
    let retainedWorkspace = try XCTUnwrap(seededPolicyStore.settings.workspaces.last)

    seededPolicyStore.applyRememberedDecision(
      AccessPromptDecision(
        requestID: UUID(),
        decision: .deny,
        source: .user,
        rememberChoice: true,
        respondedAt: Date()
      ),
      for: makeRememberedRequest(
        workspace: removedWorkspace,
        targetPath: "/Users/removal/OpenClaw/spec.txt"
      ),
      at: Date()
    )
    seededPolicyStore.applyRememberedDecision(
      AccessPromptDecision(
        requestID: UUID(),
        decision: .allow,
        source: .user,
        rememberChoice: true,
        respondedAt: Date()
      ),
      for: makeRememberedRequest(
        workspace: retainedWorkspace,
        targetPath: "/Users/removal/HermesAgentWorkspace/spec.txt"
      ),
      at: Date()
    )
    try await fileStore.save(seededPolicyStore)

    let runtime = makeRuntime(homeDirectoryPath: "/Users/removal", sharedContainerPaths: paths)

    await runtime.activate()
    XCTAssertEqual(runtime.rememberedRules.count, 2)

    await runtime.removeProtectedWorkspace(id: removedWorkspace.id)

    let storedPolicyStore = try await fileStore.load()
    let snapshot = try await AegisIPCService(paths: paths).snapshot()

    XCTAssertFalse(storedPolicyStore.settings.workspaces.contains { $0.id == removedWorkspace.id })
    XCTAssertEqual(storedPolicyStore.rememberedRules.count, 1)
    XCTAssertEqual(storedPolicyStore.rememberedRules.first?.workspaceID, retainedWorkspace.id)
    XCTAssertEqual(runtime.rememberedRules.count, 1)
    XCTAssertEqual(runtime.rememberedRules.first?.workspaceID, retainedWorkspace.id)
    XCTAssertNotNil(snapshot.lastPolicyReloadAt)
  }

  @MainActor
  func testDiagnosticItemsExposeEndpointDetailsAndLastExtensionDiagnostic() async {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let paths = SharedContainerPaths.temporary(named: UUID().uuidString)
    let controller = FileBackedAppIPCController(paths: paths)
    let registrar = FakeAgentLoginItemRegistrar(initialState: .enabled)
    let runtime = AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: "/Users/diagnostics",
        forcedOnboardingCompleted: true,
        sharedContainerPaths: paths,
        agentLoginItemRegistrar: registrar,
        ipcController: controller
      )
    )

    let snapshot = IPCStatusSnapshot(
      app: .init(state: .ready, detail: "app-ready", updatedAt: Date()),
      agent: .init(state: .unavailable, detail: "xpc-invalidated", updatedAt: Date()),
      extensionService: .init(
        state: .busy,
        detail: "endpoint-security-subscribing",
        updatedAt: Date()
      ),
      loginItemEnabled: true,
      pendingPromptCount: 0,
      lastPolicyReloadAt: nil
    )
    let diagnostic = ExtensionDiagnosticEvent(
      messageKey: "aegis.extension.endpoint-security.not-permitted",
      metadata: [
        "detail": "es-client-not-permitted",
        "code": "notPermitted",
      ],
      occurredAt: Date(timeIntervalSince1970: 1_234)
    )

    controller.onStatusDidChange?(snapshot)
    controller.onDiagnosticEvent?(diagnostic)
    await Task.yield()
    await Task.yield()

    let agentState = runtime.diagnosticItems.first { $0.id == "agent-state" }
    let extensionState = runtime.diagnosticItems.first { $0.id == "extension-state" }

    XCTAssertEqual(runtime.lastExtensionDiagnostic, diagnostic)
    XCTAssertTrue(agentState?.value.contains("xpc-invalidated") == true)
    XCTAssertTrue(extensionState?.value.contains("endpoint-security-subscribing") == true)
    XCTAssertTrue(
      extensionState?.value.contains("aegis.extension.endpoint-security.not-permitted") == true)
    XCTAssertTrue(extensionState?.value.contains("es-client-not-permitted") == true)
    XCTAssertTrue(extensionState?.value.contains("notPermitted") == true)
  }

  @MainActor
  private func makeRuntime(
    homeDirectoryPath: String,
    sharedContainerPaths: SharedContainerPaths = .temporary(named: UUID().uuidString),
    agentLoginItemRegistrar: FakeAgentLoginItemRegistrar = .init()
  ) -> AppRuntime {
    let suiteName = "AegisAppTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)

    return AppRuntime(
      configuration: makeConfiguration(
        defaults: defaults,
        homeDirectoryPath: homeDirectoryPath,
        forcedOnboardingCompleted: nil,
        sharedContainerPaths: sharedContainerPaths,
        agentLoginItemRegistrar: agentLoginItemRegistrar
      )
    )
  }

  @MainActor
  private func makeConfiguration(
    defaults: UserDefaults,
    homeDirectoryPath: String,
    forcedOnboardingCompleted: Bool?,
    isUITesting: Bool = false,
    sharedContainerPaths: SharedContainerPaths = .temporary(named: UUID().uuidString),
    agentLoginItemRegistrar: FakeAgentLoginItemRegistrar = .init(),
    ipcController: (any AppIPCControlling)? = nil
  ) -> AppRuntime.Configuration {
    .init(
      userDefaults: defaults,
      homeDirectoryURL: URL(fileURLWithPath: homeDirectoryPath, isDirectory: true),
      forcedOnboardingCompleted: forcedOnboardingCompleted,
      isUITesting: isUITesting,
      sharedContainerPaths: sharedContainerPaths,
      ipcController: ipcController ?? FileBackedAppIPCController(paths: sharedContainerPaths),
      agentLoginItemStatusProvider: { agentLoginItemRegistrar.status() },
      registerAgentLoginItemAction: { agentLoginItemRegistrar.register() },
      unregisterAgentLoginItemAction: { agentLoginItemRegistrar.unregister() }
    )
  }

  private func makeRememberedRequest(
    workspace: ProtectedWorkspace,
    targetPath: String
  ) -> AccessPromptRequest {
    AccessPromptRequest(
      requestID: UUID(),
      eventType: AccessEventType.authOpen,
      targetPath: targetPath,
      workspaceID: workspace.id,
      workspaceName: workspace.name,
      processPath: "/Applications/Example.app/Contents/MacOS/Example",
      pid: 7,
      signingIdentifier: "com.nanzhipro.example",
      teamIdentifier: "ABCDE12345",
      isAppleSigned: false,
      deadline: Date().addingTimeInterval(5)
    )
  }
}
