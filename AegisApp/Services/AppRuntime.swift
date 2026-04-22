import Foundation
import Observation

@MainActor
@Observable
public final class AppRuntime {
  public struct Configuration {
    public var userDefaults: UserDefaults
    public var homeDirectoryURL: URL
    public var forcedOnboardingCompleted: Bool?
    public var forcedPseudolocalization: Bool
    public var isUITesting: Bool
    public var sharedContainerPaths: SharedContainerPaths

    public init(
      userDefaults: UserDefaults,
      homeDirectoryURL: URL,
      forcedOnboardingCompleted: Bool?,
      forcedPseudolocalization: Bool = false,
      isUITesting: Bool = false,
      sharedContainerPaths: SharedContainerPaths = .defaultRoot()
    ) {
      self.userDefaults = userDefaults
      self.homeDirectoryURL = homeDirectoryURL
      self.forcedOnboardingCompleted = forcedOnboardingCompleted
      self.forcedPseudolocalization = forcedPseudolocalization
      self.isUITesting = isUITesting
      self.sharedContainerPaths = sharedContainerPaths
    }

    public static func live(
      processInfo: ProcessInfo = .processInfo,
      fileManager: FileManager = .default
    ) -> Configuration {
      let suiteName = processInfo.environment["AEGIS_USER_DEFAULTS_SUITE"]
      let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
      let forcedOnboardingCompleted = Self.parseBoolean(
        processInfo.environment["AEGIS_FORCE_ONBOARDING_COMPLETED"])
      let forcedPseudolocalization =
        Self.parseBoolean(processInfo.environment["AEGIS_FORCE_PSEUDO_LANGUAGE"]) ?? false
      let isUITesting = Self.parseBoolean(processInfo.environment["AEGIS_UI_TEST_MODE"]) ?? false
      let homeDirectoryURL =
        processInfo.environment["AEGIS_TEST_HOME_PATH"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? fileManager.homeDirectoryForCurrentUser
      let sharedContainerPaths =
        processInfo.environment["AEGIS_SHARED_CONTAINER_ROOT"]
        .map { SharedContainerPaths(rootDirectoryURL: URL(fileURLWithPath: $0, isDirectory: true)) }
        ?? .defaultRoot(fileManager: fileManager)

      return Configuration(
        userDefaults: defaults,
        homeDirectoryURL: homeDirectoryURL,
        forcedOnboardingCompleted: forcedOnboardingCompleted,
        forcedPseudolocalization: forcedPseudolocalization,
        isUITesting: isUITesting,
        sharedContainerPaths: sharedContainerPaths
      )
    }

    private static func parseBoolean(_ rawValue: String?) -> Bool? {
      guard let rawValue else {
        return nil
      }

      switch rawValue.lowercased() {
      case "1", "true", "yes":
        return true
      case "0", "false", "no":
        return false
      default:
        return nil
      }
    }
  }

  public enum Screen: Equatable {
    case onboarding
    case dashboard
  }

  enum SidebarItem: String, CaseIterable, Hashable, Identifiable {
    case overview
    case protectedFolders

    var id: Self { self }

    var titleKey: String {
      switch self {
      case .overview:
        return "aegis.sidebar.overview"
      case .protectedFolders:
        return "aegis.sidebar.workspaces"
      }
    }

    var symbolName: String {
      switch self {
      case .overview:
        return "checklist"
      case .protectedFolders:
        return "folder.badge.shield.checkmark"
      }
    }
  }

  enum OnboardingStep: Int, CaseIterable, Hashable, Identifiable {
    case welcome
    case permissions
    case workspaces

    var id: Self { self }

    var titleKey: String {
      switch self {
      case .welcome:
        return "aegis.onboarding.welcome.title"
      case .permissions:
        return "aegis.onboarding.permissions.title"
      case .workspaces:
        return "aegis.onboarding.workspaces.title"
      }
    }

    var symbolName: String {
      switch self {
      case .welcome:
        return "hand.wave"
      case .permissions:
        return "lock.shield"
      case .workspaces:
        return "folder"
      }
    }
  }

  public struct ReadinessItem: Identifiable, Hashable {
    public enum Kind: String, Hashable {
      case systemExtension
      case loginItem
      case policy
      case protectionReadiness

      var titleKey: String {
        switch self {
        case .systemExtension:
          return "aegis.readiness.system_extension.title"
        case .loginItem:
          return "aegis.readiness.login_item.title"
        case .policy:
          return "aegis.readiness.policy.title"
        case .protectionReadiness:
          return "aegis.readiness.protection.title"
        }
      }

      var symbolName: String {
        switch self {
        case .systemExtension:
          return "puzzlepiece.extension"
        case .loginItem:
          return "person.crop.circle.badge.checkmark"
        case .policy:
          return "folder.badge.gearshape"
        case .protectionReadiness:
          return "shield.lefthalf.filled"
        }
      }
    }

    public let kind: Kind
    public let indicator: ComponentStatus.Indicator

    public var id: Kind { kind }
  }

  public struct DiagnosticItem: Identifiable, Hashable {
    public let id: String
    public let titleKey: String
    public let value: String

    public init(id: String, titleKey: String, value: String) {
      self.id = id
      self.titleKey = titleKey
      self.value = value
    }
  }

  public static let onboardingCompletedKey = "Aegis.onboardingCompleted"
  static let agentLoginItemEnabledKey = "Aegis.agentLoginItemEnabled"

  private let userDefaults: UserDefaults
  private let homeDirectoryURL: URL
  private let ipcService: AegisIPCService
  private let policyStoreFileStore: LocalPolicyStoreFileStore
  private let localPolicyStoreURL: URL
  private let isUITesting: Bool

  var selectedSidebarItem: SidebarItem = .overview
  var selectedOnboardingStep: OnboardingStep = .welcome
  private(set) var policyStore: LocalPolicyStore
  private(set) var componentStatus: ComponentStatus
  private(set) var hasCompletedOnboarding: Bool
  let isPseudolocalizationEnabled: Bool
  private(set) var ipcStatusSnapshot: IPCStatusSnapshot
  private(set) var isAgentLoginItemEnabled: Bool

  private static let diagnosticDateFormatter = ISO8601DateFormatter()

  public init(configuration: Configuration = .live()) {
    let loginItemEnabled = configuration.userDefaults.bool(forKey: Self.agentLoginItemEnabledKey)
    let policyStoreURL = configuration.sharedContainerPaths.policyStoreURL

    self.userDefaults = configuration.userDefaults
    self.homeDirectoryURL = configuration.homeDirectoryURL
    self.isPseudolocalizationEnabled = configuration.forcedPseudolocalization
    self.isUITesting = configuration.isUITesting
    self.ipcService = AegisIPCService(paths: configuration.sharedContainerPaths)
    self.policyStoreFileStore = LocalPolicyStoreFileStore(fileURL: policyStoreURL)
    self.localPolicyStoreURL = policyStoreURL
    self.isAgentLoginItemEnabled = loginItemEnabled
    self.ipcStatusSnapshot = .empty()

    let initialPolicyStore = LocalPolicyStore.defaultStore(
      homeDirectoryURL: configuration.homeDirectoryURL)
    self.policyStore = initialPolicyStore
    self.componentStatus = Self.makeComponentStatus(
      for: initialPolicyStore, loginItemEnabled: loginItemEnabled, extensionState: .unknown)
    self.hasCompletedOnboarding =
      configuration.forcedOnboardingCompleted
      ?? configuration.userDefaults.bool(forKey: Self.onboardingCompletedKey)
  }

  public var screen: Screen {
    hasCompletedOnboarding ? .dashboard : .onboarding
  }

  var onboardingSteps: [OnboardingStep] {
    OnboardingStep.allCases
  }

  var currentOnboardingStepNumber: Int {
    selectedOnboardingStep.rawValue + 1
  }

  var canMoveBackwardInOnboarding: Bool {
    selectedOnboardingStep.rawValue > 0
  }

  var primaryOnboardingActionKey: String {
    selectedOnboardingStep == onboardingSteps.last
      ? "aegis.onboarding.open_dashboard" : "aegis.onboarding.continue"
  }

  public var readinessItems: [ReadinessItem] {
    [
      ReadinessItem(kind: .systemExtension, indicator: componentStatus.systemExtension),
      ReadinessItem(kind: .loginItem, indicator: componentStatus.loginItem),
      ReadinessItem(kind: .policy, indicator: componentStatus.policy),
      ReadinessItem(kind: .protectionReadiness, indicator: componentStatus.protectionReadiness),
    ]
  }

  var readinessSummaryKey: String {
    componentStatus.protectionReadiness.state == .ready
      ? "aegis.readiness.summary.ready"
      : "aegis.readiness.summary.attention"
  }

  public var protectedWorkspaces: [ProtectedWorkspace] {
    policyStore.settings.workspaces
  }

  public var rememberedRules: [RememberedDecisionRule] {
    policyStore.rememberedRules.sorted { $0.updatedAt > $1.updatedAt }
  }

  public var defaultTimeoutDecision: AccessDecision {
    policyStore.settings.defaultTimeoutDecision
  }

  public var defaultTimeoutDecisionKey: String {
    switch policyStore.settings.defaultTimeoutDecision {
    case .allow:
      return "aegis.policy.decision.allow"
    case .deny:
      return "aegis.policy.decision.deny"
    }
  }

  var loginItemActionKey: String {
    isAgentLoginItemEnabled
      ? "aegis.dashboard.disable_login_item" : "aegis.dashboard.enable_login_item"
  }

  var diagnosticItems: [DiagnosticItem] {
    [
      DiagnosticItem(
        id: "policy-store-path",
        titleKey: "aegis.settings.diagnostics.policy_store_path",
        value: localPolicyStoreURL.path
      ),
      DiagnosticItem(
        id: "remembered-count",
        titleKey: "aegis.settings.diagnostics.remembered_count",
        value: String(policyStore.rememberedRules.count)
      ),
      DiagnosticItem(
        id: "last-policy-reload",
        titleKey: "aegis.settings.diagnostics.last_policy_reload",
        value: lastPolicyReloadDescription
      ),
      DiagnosticItem(
        id: "pending-prompts",
        titleKey: "aegis.settings.diagnostics.pending_prompts",
        value: String(ipcStatusSnapshot.pendingPromptCount)
      ),
      DiagnosticItem(
        id: "agent-state",
        titleKey: "aegis.settings.diagnostics.agent_state",
        value: localizedLabel(for: ipcStatusSnapshot.agent.state)
      ),
      DiagnosticItem(
        id: "extension-state",
        titleKey: "aegis.readiness.system_extension.title",
        value: localizedLabel(for: ipcStatusSnapshot.extensionService.state)
      ),
    ]
  }

  func activate() async {
    if isUITesting {
      return
    }

    let fallbackPolicyStore = LocalPolicyStore.defaultStore(homeDirectoryURL: homeDirectoryURL)
    var shouldPersistLoadedStore = !FileManager.default.fileExists(atPath: localPolicyStoreURL.path)

    do {
      policyStore = try await policyStoreFileStore.load(defaultingTo: fallbackPolicyStore)
    } catch {
      policyStore = fallbackPolicyStore
      shouldPersistLoadedStore = true
    }

    if shouldPersistLoadedStore {
      do {
        try await policyStoreFileStore.save(policyStore)
        ipcStatusSnapshot = try await ipcService.reloadPolicy()
      } catch {
        // Keep the in-memory store so the UI stays functional even if persistence fails.
      }
    }

    applyIPCStatusSnapshot()
    await refreshCommunicationStatus()
  }

  func registerAgentLoginItem() async {
    isAgentLoginItemEnabled = true
    userDefaults.set(true, forKey: Self.agentLoginItemEnabledKey)

    do {
      ipcStatusSnapshot = try await ipcService.setLoginItemEnabled(true)
      applyIPCStatusSnapshot()
    } catch {
      componentStatus.loginItem = .init(
        state: .needsAttention, detail: "aegis.readiness.login_item.detail")
    }
  }

  func unregisterAgentLoginItem() async {
    isAgentLoginItemEnabled = false
    userDefaults.set(false, forKey: Self.agentLoginItemEnabledKey)

    do {
      ipcStatusSnapshot = try await ipcService.setLoginItemEnabled(false)
      applyIPCStatusSnapshot()
    } catch {
      componentStatus.loginItem = .init(
        state: .needsAttention, detail: "aegis.readiness.login_item.detail")
    }
  }

  func refreshCommunicationStatus() async {
    do {
      ipcStatusSnapshot = try await ipcService.snapshot()
      applyIPCStatusSnapshot()
    } catch {
      componentStatus.systemExtension = .init(
        state: .needsAttention, detail: "aegis.readiness.system_extension.detail")
    }
  }

  func addProtectedWorkspace() async {
    let nextIndex = policyStore.settings.workspaces.count + 1
    let normalizer = PathNormalizer(homeDirectoryURL: homeDirectoryURL)
    let folderName = "ProtectedFolder\(nextIndex)"
    let workspace = ProtectedWorkspace(
      id: UUID(),
      name: "\(String(localized: "aegis.settings.new_folder_name")) \(nextIndex)",
      path: normalizer.normalize(
        homeDirectoryURL.appendingPathComponent(folderName, isDirectory: true).path),
      isEnabled: true
    )

    policyStore.settings.workspaces.append(workspace)
    await persistPolicyStoreAndReload()
  }

  func saveProtectedWorkspace(
    id: UUID,
    name: String,
    path: String,
    isEnabled: Bool
  ) async {
    guard let workspaceIndex = policyStore.settings.workspaces.firstIndex(where: { $0.id == id })
    else {
      return
    }

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedPath = PathNormalizer(homeDirectoryURL: homeDirectoryURL).normalize(path)

    guard !trimmedName.isEmpty, !normalizedPath.isEmpty else {
      return
    }

    policyStore.settings.workspaces[workspaceIndex].name = trimmedName
    policyStore.settings.workspaces[workspaceIndex].path = normalizedPath
    policyStore.settings.workspaces[workspaceIndex].isEnabled = isEnabled
    await persistPolicyStoreAndReload()
  }

  func removeProtectedWorkspace(id: UUID) async {
    guard policyStore.settings.workspaces.contains(where: { $0.id == id }) else {
      return
    }

    policyStore.settings.workspaces.removeAll { $0.id == id }
    policyStore.clearRememberedDecisions(workspaceID: id)
    await persistPolicyStoreAndReload()
  }

  func setDefaultTimeoutDecision(_ decision: AccessDecision) async {
    guard policyStore.settings.defaultTimeoutDecision != decision else {
      return
    }

    policyStore.settings.defaultTimeoutDecision = decision
    await persistPolicyStoreAndReload()
  }

  func clearRememberedDecisions() async {
    guard !policyStore.rememberedRules.isEmpty else {
      return
    }

    policyStore.clearRememberedDecisions()
    await persistPolicyStoreAndReload()
  }

  func goBack() {
    guard canMoveBackwardInOnboarding,
      let previous = OnboardingStep(rawValue: selectedOnboardingStep.rawValue - 1)
    else {
      return
    }

    selectedOnboardingStep = previous
  }

  func advanceOnboarding() {
    guard let next = OnboardingStep(rawValue: selectedOnboardingStep.rawValue + 1) else {
      completeOnboarding()
      return
    }

    selectedOnboardingStep = next
  }

  public func completeOnboarding() {
    hasCompletedOnboarding = true
    selectedSidebarItem = .overview
    userDefaults.set(true, forKey: Self.onboardingCompletedKey)
  }

  func reopenOnboarding() {
    hasCompletedOnboarding = false
    selectedOnboardingStep = .welcome
    userDefaults.set(false, forKey: Self.onboardingCompletedKey)
  }

  func workspaceDisplayName(for workspaceID: UUID) -> String {
    policyStore.settings.workspaces.first(where: { $0.id == workspaceID })?.name
      ?? workspaceID.uuidString
  }

  func formattedDiagnosticDate(_ date: Date) -> String {
    Self.diagnosticDateFormatter.string(from: date)
  }

  private static func makeComponentStatus(
    for policyStore: LocalPolicyStore,
    loginItemEnabled: Bool,
    extensionState: IPCServiceState
  ) -> ComponentStatus {
    let hasConfiguredWorkspaces = !policyStore.settings.workspaces.isEmpty

    let policyIndicator = ComponentStatus.Indicator(
      state: hasConfiguredWorkspaces ? .ready : .needsAttention,
      detail: hasConfiguredWorkspaces
        ? "aegis.readiness.policy.detail"
        : "aegis.readiness.policy.detail.missing"
    )

    let loginItemIndicator = ComponentStatus.Indicator(
      state: loginItemEnabled ? .ready : .needsAttention,
      detail: loginItemEnabled
        ? "aegis.readiness.login_item.enabled"
        : "aegis.readiness.login_item.detail"
    )

    let systemExtensionIndicator = ComponentStatus.Indicator(
      state: extensionState == .ready ? .ready : .needsAttention,
      detail: extensionState == .ready
        ? "aegis.readiness.system_extension.ready"
        : "aegis.readiness.system_extension.detail"
    )

    let protectionState: ComponentStatus.State
    if hasConfiguredWorkspaces && loginItemEnabled && extensionState == .ready {
      protectionState = .ready
    } else if hasConfiguredWorkspaces {
      protectionState = .needsAttention
    } else {
      protectionState = .unavailable
    }

    return ComponentStatus(
      systemExtension: systemExtensionIndicator,
      loginItem: loginItemIndicator,
      policy: policyIndicator,
      protectionReadiness: .init(
        state: protectionState,
        detail: protectionState == .ready
          ? "aegis.readiness.protection.detail.ready"
          : hasConfiguredWorkspaces
            ? "aegis.readiness.protection.detail"
            : "aegis.readiness.protection.detail.missing"
      )
    )
  }

  private func applyIPCStatusSnapshot() {
    componentStatus = Self.makeComponentStatus(
      for: policyStore,
      loginItemEnabled: isAgentLoginItemEnabled,
      extensionState: ipcStatusSnapshot.extensionService.state
    )
  }

  private func persistPolicyStoreAndReload() async {
    do {
      try await policyStoreFileStore.save(policyStore)
    } catch {
      return
    }

    do {
      ipcStatusSnapshot = try await ipcService.reloadPolicy()
    } catch {
      // Persisted changes still take effect locally even if the reload signal cannot be delivered.
    }

    applyIPCStatusSnapshot()
  }

  private var lastPolicyReloadDescription: String {
    guard let lastPolicyReloadAt = ipcStatusSnapshot.lastPolicyReloadAt else {
      return String(localized: "aegis.settings.diagnostics.not_reloaded")
    }

    return formattedDiagnosticDate(lastPolicyReloadAt)
  }

  private func localizedLabel(for state: IPCServiceState) -> String {
    switch state.componentState {
    case .ready:
      return String(localized: "aegis.state.ready")
    case .needsAttention:
      return String(localized: "aegis.state.needs_attention")
    case .unavailable:
      return String(localized: "aegis.state.unavailable")
    case .unknown:
      return String(localized: "aegis.state.unknown")
    }
  }
}
