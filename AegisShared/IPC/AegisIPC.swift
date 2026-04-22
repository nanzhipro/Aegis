import Foundation

public enum IPCServiceEndpoint: String, Codable, Hashable, Sendable, CaseIterable {
  case app
  case agent
  case extensionService
}

public enum IPCServiceState: String, Codable, Hashable, Sendable, CaseIterable {
  case unknown
  case ready
  case busy
  case unavailable

  public var componentState: ComponentStatus.State {
    switch self {
    case .unknown:
      return .unknown
    case .ready:
      return .ready
    case .busy:
      return .needsAttention
    case .unavailable:
      return .unavailable
    }
  }
}

public enum IPCTransportError: String, Error, Codable, Hashable, Sendable {
  case agentUnavailable
  case timedOut
  case invalidResponse
  case requestNotFound
  case storeFailure
}

public struct IPCServiceEndpointSnapshot: Codable, Hashable, Sendable {
  public var state: IPCServiceState
  public var detail: String?
  public var updatedAt: Date?

  public init(state: IPCServiceState, detail: String? = nil, updatedAt: Date? = nil) {
    self.state = state
    self.detail = detail
    self.updatedAt = updatedAt
  }
}

public struct IPCStatusSnapshot: Codable, Hashable, Sendable {
  public var app: IPCServiceEndpointSnapshot
  public var agent: IPCServiceEndpointSnapshot
  public var extensionService: IPCServiceEndpointSnapshot
  public var loginItemEnabled: Bool
  public var pendingPromptCount: Int
  public var lastPolicyReloadAt: Date?

  public init(
    app: IPCServiceEndpointSnapshot,
    agent: IPCServiceEndpointSnapshot,
    extensionService: IPCServiceEndpointSnapshot,
    loginItemEnabled: Bool,
    pendingPromptCount: Int,
    lastPolicyReloadAt: Date?
  ) {
    self.app = app
    self.agent = agent
    self.extensionService = extensionService
    self.loginItemEnabled = loginItemEnabled
    self.pendingPromptCount = pendingPromptCount
    self.lastPolicyReloadAt = lastPolicyReloadAt
  }

  public static func empty(now: Date = Date()) -> IPCStatusSnapshot {
    IPCStatusSnapshot(
      app: .init(state: .unknown, detail: "app-idle", updatedAt: now),
      agent: .init(state: .unavailable, detail: "agent-offline", updatedAt: now),
      extensionService: .init(state: .unknown, detail: "extension-idle", updatedAt: now),
      loginItemEnabled: false,
      pendingPromptCount: 0,
      lastPolicyReloadAt: nil
    )
  }

  public func snapshot(for endpoint: IPCServiceEndpoint) -> IPCServiceEndpointSnapshot {
    switch endpoint {
    case .app:
      return app
    case .agent:
      return agent
    case .extensionService:
      return extensionService
    }
  }

  public mutating func update(
    endpoint: IPCServiceEndpoint,
    state: IPCServiceState,
    detail: String?,
    at timestamp: Date
  ) {
    let updatedSnapshot = IPCServiceEndpointSnapshot(
      state: state, detail: detail, updatedAt: timestamp)

    switch endpoint {
    case .app:
      app = updatedSnapshot
    case .agent:
      agent = updatedSnapshot
    case .extensionService:
      extensionService = updatedSnapshot
    }
  }
}

public struct SharedContainerPaths: Hashable, Sendable {
  public let rootDirectoryURL: URL

  public init(rootDirectoryURL: URL) {
    self.rootDirectoryURL = rootDirectoryURL
  }

  public var policyStoreURL: URL {
    rootDirectoryURL.appendingPathComponent(
      SharedPolicyDefaults.localPolicyStoreFileName, isDirectory: false)
  }

  public var ipcDirectoryURL: URL {
    rootDirectoryURL.appendingPathComponent("IPC", isDirectory: true)
  }

  public var ipcStateFileURL: URL {
    ipcDirectoryURL.appendingPathComponent("IPCState.json", isDirectory: false)
  }

  public static func defaultRoot(fileManager: FileManager = .default) -> SharedContainerPaths {
    let applicationSupportURL =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)

    return SharedContainerPaths(
      rootDirectoryURL: applicationSupportURL.appendingPathComponent("Aegis", isDirectory: true)
    )
  }

  public static func temporary(named name: String = UUID().uuidString) -> SharedContainerPaths {
    SharedContainerPaths(
      rootDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(
        "Aegis-\(name)", isDirectory: true)
    )
  }
}

private struct PromptQueueEntry: Codable, Hashable, Sendable {
  var request: AccessPromptRequest
  var enqueuedAt: Date
}

private struct PersistedIPCState: Codable, Hashable, Sendable {
  var queuedRequests: [PromptQueueEntry]
  var claimedRequests: [AccessPromptRequest]
  var responses: [AccessPromptDecision]
  var snapshot: IPCStatusSnapshot

  static func empty(now: Date = Date()) -> PersistedIPCState {
    PersistedIPCState(
      queuedRequests: [],
      claimedRequests: [],
      responses: [],
      snapshot: .empty(now: now)
    )
  }
}

public actor AegisIPCService {
  public let paths: SharedContainerPaths
  private let policyStoreFileStore: LocalPolicyStoreFileStore

  public init(paths: SharedContainerPaths, policyStoreFileStore: LocalPolicyStoreFileStore? = nil) {
    self.paths = paths
    self.policyStoreFileStore =
      policyStoreFileStore ?? LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL)
  }

  public func snapshot() throws -> IPCStatusSnapshot {
    try loadState().snapshot
  }

  public func publish(
    endpoint: IPCServiceEndpoint,
    state: IPCServiceState,
    detail: String? = nil,
    at timestamp: Date = Date()
  ) throws -> IPCStatusSnapshot {
    try mutateState { persistedState in
      persistedState.snapshot.update(
        endpoint: endpoint, state: state, detail: detail, at: timestamp)
      return persistedState.snapshot
    }
  }

  public func setLoginItemEnabled(
    _ isEnabled: Bool,
    at timestamp: Date = Date()
  ) throws -> IPCStatusSnapshot {
    try mutateState { persistedState in
      persistedState.snapshot.loginItemEnabled = isEnabled
      persistedState.snapshot.update(
        endpoint: .app,
        state: .ready,
        detail: isEnabled ? "login-item-enabled" : "login-item-disabled",
        at: timestamp
      )

      if !isEnabled {
        persistedState.snapshot.update(
          endpoint: .agent, state: .unavailable, detail: "agent-awaiting-login-item", at: timestamp)
      }

      return persistedState.snapshot
    }
  }

  public func enqueuePrompt(
    _ request: AccessPromptRequest,
    at timestamp: Date = Date()
  ) throws -> IPCStatusSnapshot {
    try mutateState { persistedState in
      guard persistedState.snapshot.loginItemEnabled,
        persistedState.snapshot.agent.state != .unavailable
      else {
        throw IPCTransportError.agentUnavailable
      }

      persistedState.queuedRequests.append(
        PromptQueueEntry(request: request, enqueuedAt: timestamp))
      persistedState.snapshot.pendingPromptCount = persistedState.queuedRequests.count
      persistedState.snapshot.update(
        endpoint: .extensionService, state: .busy, detail: "prompt-enqueued", at: timestamp)
      return persistedState.snapshot
    }
  }

  public func claimNextPrompt(at timestamp: Date = Date()) throws -> AccessPromptRequest? {
    try mutateState { persistedState in
      guard !persistedState.queuedRequests.isEmpty else {
        let idleDetail =
          persistedState.snapshot.loginItemEnabled ? "agent-idle" : "agent-awaiting-login-item"
        let idleState: IPCServiceState =
          persistedState.snapshot.loginItemEnabled ? .ready : .unavailable
        persistedState.snapshot.update(
          endpoint: .agent, state: idleState, detail: idleDetail, at: timestamp)
        return nil
      }

      let nextEntry = persistedState.queuedRequests.removeFirst()
      persistedState.claimedRequests.append(nextEntry.request)
      persistedState.snapshot.pendingPromptCount = persistedState.queuedRequests.count
      persistedState.snapshot.update(
        endpoint: .agent, state: .busy, detail: "prompt-presenting", at: timestamp)
      return nextEntry.request
    }
  }

  public func submitDecision(
    _ decision: AccessPromptDecision,
    for request: AccessPromptRequest,
    at timestamp: Date = Date()
  ) async throws -> IPCStatusSnapshot {
    guard decision.requestID == request.requestID else {
      throw IPCTransportError.invalidResponse
    }

    let snapshot = try mutateState { persistedState in
      guard
        let claimedIndex = persistedState.claimedRequests.lastIndex(where: {
          $0.requestID == request.requestID
        })
      else {
        throw IPCTransportError.requestNotFound
      }

      persistedState.claimedRequests.remove(at: claimedIndex)
      persistedState.responses.append(decision)
      persistedState.snapshot.update(
        endpoint: .agent, state: .ready, detail: "decision-submitted", at: timestamp)
      persistedState.snapshot.update(
        endpoint: .extensionService, state: .ready, detail: "decision-ready", at: timestamp)
      return persistedState.snapshot
    }

    if decision.rememberChoice {
      var store = try await policyStoreFileStore.load()
      store.applyRememberedDecision(decision, for: request, at: timestamp)
      try await policyStoreFileStore.save(store)
    }

    return snapshot
  }

  public func awaitDecision(
    for request: AccessPromptRequest,
    pollIntervalNanoseconds: UInt64 = 50_000_000,
    now: @escaping @Sendable () -> Date = { Date() }
  ) async throws -> AccessPromptDecision {
    while now() <= request.deadline {
      if let decision = try takeDecision(for: request.requestID) {
        return decision
      }

      try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    throw IPCTransportError.timedOut
  }

  public func reloadPolicy(at timestamp: Date = Date()) throws -> IPCStatusSnapshot {
    try mutateState { persistedState in
      persistedState.snapshot.lastPolicyReloadAt = timestamp
      persistedState.snapshot.update(
        endpoint: .extensionService, state: .ready, detail: "policy-reloaded", at: timestamp)
      return persistedState.snapshot
    }
  }

  private func takeDecision(for requestID: UUID) throws -> AccessPromptDecision? {
    try mutateState { persistedState in
      guard
        let responseIndex = persistedState.responses.lastIndex(where: { $0.requestID == requestID })
      else {
        return nil
      }

      return persistedState.responses.remove(at: responseIndex)
    }
  }

  private func mutateState<T>(_ body: (inout PersistedIPCState) throws -> T) throws -> T {
    var persistedState = try loadState()
    let result = try body(&persistedState)
    try saveState(persistedState)
    return result
  }

  private func loadState(now: Date = Date()) throws -> PersistedIPCState {
    do {
      guard FileManager.default.fileExists(atPath: paths.ipcStateFileURL.path) else {
        return PersistedIPCState.empty(now: now)
      }

      let data = try Data(contentsOf: paths.ipcStateFileURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode(PersistedIPCState.self, from: data)
    } catch let error as IPCTransportError {
      throw error
    } catch {
      throw IPCTransportError.storeFailure
    }
  }

  private func saveState(_ persistedState: PersistedIPCState) throws {
    do {
      try FileManager.default.createDirectory(
        at: paths.ipcDirectoryURL, withIntermediateDirectories: true, attributes: nil)

      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(persistedState)
      try data.write(to: paths.ipcStateFileURL, options: [.atomic])
    } catch {
      throw IPCTransportError.storeFailure
    }
  }
}
