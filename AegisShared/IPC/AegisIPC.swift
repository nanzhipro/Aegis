import Foundation

public final class ExtensionDiagnosticEvent: NSObject, NSSecureCoding, Codable, @unchecked Sendable
{
  public let messageKey: String
  public let metadata: [String: String]
  public let occurredAt: Date

  public init(messageKey: String, metadata: [String: String] = [:], occurredAt: Date = Date()) {
    self.messageKey = messageKey
    self.metadata = metadata
    self.occurredAt = occurredAt
  }

  public static var supportsSecureCoding: Bool {
    true
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? ExtensionDiagnosticEvent else {
      return false
    }

    return messageKey == object.messageKey
      && metadata == object.metadata
      && occurredAt == object.occurredAt
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(messageKey)
    hasher.combine(metadata)
    hasher.combine(occurredAt)
    return hasher.finalize()
  }

  public required convenience init?(coder: NSCoder) {
    guard
      let messageKey = coder.decodeObject(of: NSString.self, forKey: "messageKey") as String?,
      let metadata = AegisSecureCodingBridge.decode(
        [String: String].self,
        from: coder.decodeObject(of: NSData.self, forKey: "metadata") as Data?),
      let occurredAt = coder.decodeObject(of: NSDate.self, forKey: "occurredAt") as Date?
    else {
      return nil
    }

    self.init(messageKey: messageKey, metadata: metadata, occurredAt: occurredAt)
  }

  public func encode(with coder: NSCoder) {
    coder.encode(messageKey as NSString, forKey: "messageKey")
    coder.encode(AegisSecureCodingBridge.encode(metadata) as NSData?, forKey: "metadata")
    coder.encode(occurredAt as NSDate, forKey: "occurredAt")
  }

  enum CodingKeys: String, CodingKey {
    case messageKey
    case metadata
    case occurredAt
  }

  public required convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      messageKey: try container.decode(String.self, forKey: .messageKey),
      metadata: try container.decode([String: String].self, forKey: .metadata),
      occurredAt: try container.decode(Date.self, forKey: .occurredAt)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(messageKey, forKey: .messageKey)
    try container.encode(metadata, forKey: .metadata)
    try container.encode(occurredAt, forKey: .occurredAt)
  }
}

@objc(AegisExtensionControlProtocol)
public protocol AegisExtensionControlProtocol {
  func publishClientReady(role: String, withReply reply: @escaping (IPCStatusSnapshot) -> Void)
  func updateLoginItemEnabled(
    _ isEnabled: Bool, withReply reply: @escaping (IPCStatusSnapshot) -> Void)
  func snapshot(withReply reply: @escaping (IPCStatusSnapshot) -> Void)
  func reloadPolicy(withReply reply: @escaping (IPCStatusSnapshot?, NSError?) -> Void)
  func submitDecision(
    _ decision: AccessPromptDecision, withReply reply: @escaping (NSError?) -> Void)
  func clearRememberedDecisions(workspaceID: NSUUID?, withReply reply: @escaping (NSError?) -> Void)
}

@objc(AegisAppObserverProtocol)
public protocol AegisAppObserverProtocol {
  func statusDidChange(_ snapshot: IPCStatusSnapshot)
  func extensionDidEmitDiagnostic(_ event: ExtensionDiagnosticEvent)
}

@objc(AegisAgentPromptProtocol)
public protocol AegisAgentPromptProtocol {
  func presentPrompt(_ request: AccessPromptRequest)
  func cancelPrompt(requestID: NSUUID)
  func policyDidReload(_ snapshot: IPCStatusSnapshot)
}

public enum AegisXPCInterfaces {
  public static func extensionControl() -> NSXPCInterface {
    let interface = NSXPCInterface(with: AegisExtensionControlProtocol.self)
    registerClasses(
      classSet([IPCStatusSnapshot.self]), on: interface,
      selector: #selector(AegisExtensionControlProtocol.publishClientReady(role:withReply:)),
      argumentIndex: 0, ofReply: true)
    registerClasses(
      classSet([IPCStatusSnapshot.self]), on: interface,
      selector: #selector(AegisExtensionControlProtocol.updateLoginItemEnabled(_:withReply:)),
      argumentIndex: 0, ofReply: true)
    registerClasses(
      classSet([IPCStatusSnapshot.self]), on: interface,
      selector: #selector(AegisExtensionControlProtocol.snapshot(withReply:)), argumentIndex: 0,
      ofReply: true)
    registerClasses(
      classSet([IPCStatusSnapshot.self]), on: interface,
      selector: #selector(AegisExtensionControlProtocol.reloadPolicy(withReply:)), argumentIndex: 0,
      ofReply: true)
    registerClasses(
      classSet([NSError.self]), on: interface,
      selector: #selector(AegisExtensionControlProtocol.reloadPolicy(withReply:)), argumentIndex: 1,
      ofReply: true)
    registerClasses(
      classSet([AccessPromptDecision.self]), on: interface,
      selector: #selector(AegisExtensionControlProtocol.submitDecision(_:withReply:)),
      argumentIndex: 0, ofReply: false)
    registerClasses(
      classSet([NSError.self]), on: interface,
      selector: #selector(AegisExtensionControlProtocol.submitDecision(_:withReply:)),
      argumentIndex: 0, ofReply: true)
    registerClasses(
      classSet([NSUUID.self]), on: interface,
      selector: #selector(
        AegisExtensionControlProtocol.clearRememberedDecisions(workspaceID:withReply:)),
      argumentIndex: 0, ofReply: false)
    registerClasses(
      classSet([NSError.self]), on: interface,
      selector: #selector(
        AegisExtensionControlProtocol.clearRememberedDecisions(workspaceID:withReply:)),
      argumentIndex: 0, ofReply: true)
    return interface
  }

  public static func appObserver() -> NSXPCInterface {
    let interface = NSXPCInterface(with: AegisAppObserverProtocol.self)
    registerClasses(
      classSet([IPCStatusSnapshot.self]), on: interface,
      selector: #selector(AegisAppObserverProtocol.statusDidChange(_:)), argumentIndex: 0,
      ofReply: false)
    registerClasses(
      classSet([ExtensionDiagnosticEvent.self]), on: interface,
      selector: #selector(AegisAppObserverProtocol.extensionDidEmitDiagnostic(_:)),
      argumentIndex: 0, ofReply: false)
    return interface
  }

  public static func agentPrompt() -> NSXPCInterface {
    let interface = NSXPCInterface(with: AegisAgentPromptProtocol.self)
    registerClasses(
      classSet([AccessPromptRequest.self]), on: interface,
      selector: #selector(AegisAgentPromptProtocol.presentPrompt(_:)), argumentIndex: 0,
      ofReply: false)
    registerClasses(
      classSet([NSUUID.self]), on: interface,
      selector: #selector(AegisAgentPromptProtocol.cancelPrompt(requestID:)), argumentIndex: 0,
      ofReply: false)
    registerClasses(
      classSet([IPCStatusSnapshot.self]), on: interface,
      selector: #selector(AegisAgentPromptProtocol.policyDidReload(_:)), argumentIndex: 0,
      ofReply: false)
    return interface
  }

  private static func registerClasses(
    _ classes: Set<AnyHashable>,
    on interface: NSXPCInterface,
    selector: Selector,
    argumentIndex: Int,
    ofReply: Bool
  ) {
    interface.setClasses(classes, for: selector, argumentIndex: argumentIndex, ofReply: ofReply)
  }

  private static func classSet(_ classes: [AnyClass]) -> Set<AnyHashable> {
    (NSSet(array: classes) as? Set<AnyHashable>) ?? []
  }
}

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

public enum AegisXPCClientRole: String, Codable, Hashable, Sendable {
  case app
  case agent
}

public enum AegisExtensionXPCListenerMode: Hashable, Sendable {
  case anonymous
  case machService(name: String)
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

public final class IPCStatusSnapshot: NSObject, NSSecureCoding, Codable, @unchecked Sendable {
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

  public static var supportsSecureCoding: Bool {
    true
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? IPCStatusSnapshot else {
      return false
    }

    return app == object.app
      && agent == object.agent
      && extensionService == object.extensionService
      && loginItemEnabled == object.loginItemEnabled
      && pendingPromptCount == object.pendingPromptCount
      && lastPolicyReloadAt == object.lastPolicyReloadAt
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(app)
    hasher.combine(agent)
    hasher.combine(extensionService)
    hasher.combine(loginItemEnabled)
    hasher.combine(pendingPromptCount)
    hasher.combine(lastPolicyReloadAt)
    return hasher.finalize()
  }

  public required convenience init?(coder: NSCoder) {
    guard
      let app = AegisSecureCodingBridge.decode(
        IPCServiceEndpointSnapshot.self,
        from: coder.decodeObject(of: NSData.self, forKey: "app") as Data?),
      let agent = AegisSecureCodingBridge.decode(
        IPCServiceEndpointSnapshot.self,
        from: coder.decodeObject(of: NSData.self, forKey: "agent") as Data?),
      let extensionService = AegisSecureCodingBridge.decode(
        IPCServiceEndpointSnapshot.self,
        from: coder.decodeObject(of: NSData.self, forKey: "extensionService") as Data?)
    else {
      return nil
    }

    self.init(
      app: app,
      agent: agent,
      extensionService: extensionService,
      loginItemEnabled: coder.decodeBool(forKey: "loginItemEnabled"),
      pendingPromptCount: coder.decodeInteger(forKey: "pendingPromptCount"),
      lastPolicyReloadAt: coder.decodeObject(of: NSDate.self, forKey: "lastPolicyReloadAt") as Date?
    )
  }

  public func encode(with coder: NSCoder) {
    coder.encode(AegisSecureCodingBridge.encode(app) as NSData?, forKey: "app")
    coder.encode(AegisSecureCodingBridge.encode(agent) as NSData?, forKey: "agent")
    coder.encode(
      AegisSecureCodingBridge.encode(extensionService) as NSData?,
      forKey: "extensionService"
    )
    coder.encode(loginItemEnabled, forKey: "loginItemEnabled")
    coder.encode(pendingPromptCount, forKey: "pendingPromptCount")
    coder.encode(lastPolicyReloadAt as NSDate?, forKey: "lastPolicyReloadAt")
  }

  enum CodingKeys: String, CodingKey {
    case app
    case agent
    case extensionService
    case loginItemEnabled
    case pendingPromptCount
    case lastPolicyReloadAt
  }

  public required convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      app: try container.decode(IPCServiceEndpointSnapshot.self, forKey: .app),
      agent: try container.decode(IPCServiceEndpointSnapshot.self, forKey: .agent),
      extensionService: try container.decode(
        IPCServiceEndpointSnapshot.self, forKey: .extensionService),
      loginItemEnabled: try container.decode(Bool.self, forKey: .loginItemEnabled),
      pendingPromptCount: try container.decode(Int.self, forKey: .pendingPromptCount),
      lastPolicyReloadAt: try container.decodeIfPresent(Date.self, forKey: .lastPolicyReloadAt)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(app, forKey: .app)
    try container.encode(agent, forKey: .agent)
    try container.encode(extensionService, forKey: .extensionService)
    try container.encode(loginItemEnabled, forKey: .loginItemEnabled)
    try container.encode(pendingPromptCount, forKey: .pendingPromptCount)
    try container.encodeIfPresent(lastPolicyReloadAt, forKey: .lastPolicyReloadAt)
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

  public func update(
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

public final class AegisExtensionXPCService: NSObject, NSXPCListenerDelegate,
  @unchecked Sendable
{
  public let listener: NSXPCListener
  public let listenerEndpoint: NSXPCListenerEndpoint?

  private let state: AegisExtensionXPCState
  private let acceptConnection: @Sendable (NSXPCConnection) -> Bool
  private let codeSigningRequirement: String?

  public init(
    listenerMode: AegisExtensionXPCListenerMode = .anonymous,
    paths: SharedContainerPaths = .defaultRoot(),
    policyStoreFileStore: LocalPolicyStoreFileStore? = nil,
    codeSigningRequirement: String? = nil,
    acceptConnection: @escaping @Sendable (NSXPCConnection) -> Bool = { _ in true },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    let resolvedListener: NSXPCListener
    let resolvedEndpoint: NSXPCListenerEndpoint?

    switch listenerMode {
    case .anonymous:
      let anonymousListener = NSXPCListener.anonymous()
      resolvedListener = anonymousListener
      resolvedEndpoint = anonymousListener.endpoint
    case .machService(let name):
      resolvedListener = NSXPCListener(machServiceName: name)
      resolvedEndpoint = nil
    }

    self.listener = resolvedListener
    self.listenerEndpoint = resolvedEndpoint
    self.state = AegisExtensionXPCState(
      policyStoreFileStore: policyStoreFileStore
        ?? LocalPolicyStoreFileStore(fileURL: paths.policyStoreURL),
      now: now
    )
    self.acceptConnection = acceptConnection
    self.codeSigningRequirement = codeSigningRequirement
    super.init()
    self.listener.delegate = self
  }

  public func resume() {
    listener.resume()
  }

  public func startServing() async {
    resume()
  }

  public func publishReady(detail: String) async throws -> IPCStatusSnapshot {
    try await publishExtensionStatus(state: .ready, detail: detail)
  }

  public func publishExtensionStatus(state: IPCServiceState, detail: String) async throws
    -> IPCStatusSnapshot
  {
    await self.state.publishExtensionStatus(state: state, detail: detail)
  }

  public func enqueuePrompt(_ request: AccessPromptRequest) async throws -> IPCStatusSnapshot {
    try await state.enqueuePrompt(request)
  }

  public func awaitDecision(for request: AccessPromptRequest) async throws -> AccessPromptDecision {
    try await state.awaitDecision(for: request)
  }

  public func reloadPolicy() async throws -> IPCStatusSnapshot {
    try await state.reloadPolicy()
  }

  public func snapshot() async throws -> IPCStatusSnapshot {
    await state.snapshot()
  }

  public func emitDiagnostic(_ event: ExtensionDiagnosticEvent) async {
    await state.emitDiagnostic(event)
  }

  public func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    guard acceptConnection(newConnection) else {
      newConnection.invalidate()
      return false
    }

    if let codeSigningRequirement {
      newConnection.setCodeSigningRequirement(codeSigningRequirement)
    }

    let connectionID = ObjectIdentifier(newConnection)
    let export = AegisExtensionXPCControlExport(
      connection: newConnection,
      connectionID: connectionID,
      state: state
    )

    newConnection.exportedInterface = AegisXPCInterfaces.extensionControl()
    newConnection.exportedObject = export
    newConnection.invalidationHandler = { [state] in
      Task {
        await state.connectionDidInvalidate(connectionID)
      }
    }
    newConnection.interruptionHandler = { [state] in
      Task {
        await state.connectionDidInterrupt(connectionID)
      }
    }
    newConnection.resume()
    return true
  }
}

private final class AegisExtensionXPCControlExport: NSObject, AegisExtensionControlProtocol {
  private let connection: NSXPCConnection
  private let connectionID: ObjectIdentifier
  private let state: AegisExtensionXPCState

  init(
    connection: NSXPCConnection,
    connectionID: ObjectIdentifier,
    state: AegisExtensionXPCState
  ) {
    self.connection = connection
    self.connectionID = connectionID
    self.state = state
  }

  func publishClientReady(role: String, withReply reply: @escaping (IPCStatusSnapshot) -> Void) {
    Task {
      let snapshot = await state.registerClient(
        connection: connection,
        connectionID: connectionID,
        role: role
      )
      reply(snapshot)
    }
  }

  func updateLoginItemEnabled(
    _ isEnabled: Bool, withReply reply: @escaping (IPCStatusSnapshot) -> Void
  ) {
    Task {
      let snapshot = await state.updateLoginItemEnabled(isEnabled)
      reply(snapshot)
    }
  }

  func snapshot(withReply reply: @escaping (IPCStatusSnapshot) -> Void) {
    Task {
      reply(await state.snapshot())
    }
  }

  func reloadPolicy(withReply reply: @escaping (IPCStatusSnapshot?, NSError?) -> Void) {
    Task {
      do {
        reply(try await state.reloadPolicy(), nil)
      } catch {
        reply(nil, error as NSError)
      }
    }
  }

  func submitDecision(
    _ decision: AccessPromptDecision, withReply reply: @escaping (NSError?) -> Void
  ) {
    Task {
      do {
        try await state.submitDecision(decision)
        reply(nil)
      } catch {
        reply(error as NSError)
      }
    }
  }

  func clearRememberedDecisions(workspaceID: NSUUID?, withReply reply: @escaping (NSError?) -> Void)
  {
    Task {
      do {
        try await state.clearRememberedDecisions(workspaceID: workspaceID as UUID?)
        reply(nil)
      } catch {
        reply(error as NSError)
      }
    }
  }
}

private actor AegisExtensionXPCState {
  private let policyStoreFileStore: LocalPolicyStoreFileStore
  private let now: @Sendable () -> Date

  private var statusSnapshot: IPCStatusSnapshot
  private var queuedRequests: [AccessPromptRequest] = []
  private var presentedRequest: AccessPromptRequest?
  private var responses: [UUID: AccessPromptDecision] = [:]
  private var appObserver: AegisAppObserverProtocol?
  private var appConnectionID: ObjectIdentifier?
  private var agentPrompt: AegisAgentPromptProtocol?
  private var agentConnectionID: ObjectIdentifier?
  private var connectionRoles: [ObjectIdentifier: AegisXPCClientRole] = [:]

  init(
    policyStoreFileStore: LocalPolicyStoreFileStore,
    now: @escaping @Sendable () -> Date
  ) {
    self.policyStoreFileStore = policyStoreFileStore
    self.now = now
    self.statusSnapshot = .empty(now: now())
  }

  func publishExtensionStatus(state: IPCServiceState, detail: String) -> IPCStatusSnapshot {
    statusSnapshot.update(endpoint: .extensionService, state: state, detail: detail, at: now())
    notifyAppObserver()
    return statusSnapshot
  }

  func publishExtensionReady(detail: String) -> IPCStatusSnapshot {
    publishExtensionStatus(state: .ready, detail: detail)
  }

  func registerClient(
    connection: NSXPCConnection,
    connectionID: ObjectIdentifier,
    role rawRole: String
  ) -> IPCStatusSnapshot {
    guard let role = AegisXPCClientRole(rawValue: rawRole) else {
      return statusSnapshot
    }

    connectionRoles[connectionID] = role

    switch role {
    case .app:
      connection.remoteObjectInterface = AegisXPCInterfaces.appObserver()
      appObserver =
        connection.remoteObjectProxyWithErrorHandler { _ in } as? AegisAppObserverProtocol
      appConnectionID = connectionID
      statusSnapshot.update(endpoint: .app, state: .ready, detail: "app-xpc-ready", at: now())
    case .agent:
      connection.remoteObjectInterface = AegisXPCInterfaces.agentPrompt()
      agentPrompt =
        connection.remoteObjectProxyWithErrorHandler { _ in } as? AegisAgentPromptProtocol
      agentConnectionID = connectionID
      statusSnapshot.loginItemEnabled = true
      let detail = presentedRequest == nil ? "agent-xpc-ready" : "prompt-presenting"
      let state: IPCServiceState = presentedRequest == nil ? .ready : .busy
      statusSnapshot.update(endpoint: .agent, state: state, detail: detail, at: now())
      dispatchNextPromptIfPossible()
    }

    refreshPendingPromptCount()
    notifyAppObserver()
    return statusSnapshot
  }

  func updateLoginItemEnabled(_ isEnabled: Bool) -> IPCStatusSnapshot {
    statusSnapshot.loginItemEnabled = isEnabled
    statusSnapshot.update(
      endpoint: .app,
      state: .ready,
      detail: isEnabled ? "login-item-enabled" : "login-item-disabled",
      at: now()
    )

    if isEnabled {
      let detail = presentedRequest == nil ? "agent-ready" : "prompt-presenting"
      let state: IPCServiceState = presentedRequest == nil ? .ready : .busy
      statusSnapshot.update(endpoint: .agent, state: state, detail: detail, at: now())
      dispatchNextPromptIfPossible()
    } else {
      if let presentedRequest {
        queuedRequests.insert(presentedRequest, at: 0)
        agentPrompt?.cancelPrompt(requestID: presentedRequest.requestID as NSUUID)
        self.presentedRequest = nil
      }
      statusSnapshot.update(
        endpoint: .agent,
        state: .unavailable,
        detail: "agent-awaiting-login-item",
        at: now()
      )
    }

    refreshPendingPromptCount()
    notifyAppObserver()
    return statusSnapshot
  }

  func snapshot() -> IPCStatusSnapshot {
    statusSnapshot
  }

  func enqueuePrompt(_ request: AccessPromptRequest) throws -> IPCStatusSnapshot {
    guard statusSnapshot.loginItemEnabled, agentPrompt != nil else {
      throw IPCTransportError.agentUnavailable
    }

    queuedRequests.append(request)
    statusSnapshot.update(
      endpoint: .extensionService, state: .busy, detail: "prompt-enqueued", at: now())
    dispatchNextPromptIfPossible()
    refreshPendingPromptCount()
    notifyAppObserver()
    return statusSnapshot
  }

  func submitDecision(_ decision: AccessPromptDecision) async throws {
    guard let presentedRequest else {
      throw IPCTransportError.requestNotFound
    }

    guard decision.requestID == presentedRequest.requestID else {
      throw IPCTransportError.invalidResponse
    }

    self.presentedRequest = nil
    responses[decision.requestID] = decision

    if decision.rememberChoice {
      var store = try await policyStoreFileStore.load()
      store.applyRememberedDecision(decision, for: presentedRequest, at: now())
      try await policyStoreFileStore.save(store)
    }

    statusSnapshot.update(endpoint: .agent, state: .ready, detail: "decision-submitted", at: now())
    statusSnapshot.update(
      endpoint: .extensionService, state: .ready, detail: "decision-ready", at: now())
    dispatchNextPromptIfPossible()
    refreshPendingPromptCount()
    notifyAppObserver()
  }

  func awaitDecision(
    for request: AccessPromptRequest,
    pollIntervalNanoseconds: UInt64 = 50_000_000
  ) async throws -> AccessPromptDecision {
    while now() <= request.deadline {
      if let decision = responses.removeValue(forKey: request.requestID) {
        return decision
      }

      try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    throw IPCTransportError.timedOut
  }

  func reloadPolicy() throws -> IPCStatusSnapshot {
    statusSnapshot.lastPolicyReloadAt = now()
    statusSnapshot.update(
      endpoint: .extensionService, state: .ready, detail: "policy-reloaded", at: now())
    agentPrompt?.policyDidReload(statusSnapshot)
    notifyAppObserver()
    return statusSnapshot
  }

  func clearRememberedDecisions(workspaceID: UUID?) async throws {
    var store = try await policyStoreFileStore.load()
    store.clearRememberedDecisions(workspaceID: workspaceID)
    try await policyStoreFileStore.save(store)
  }

  func emitDiagnostic(_ event: ExtensionDiagnosticEvent) {
    appObserver?.extensionDidEmitDiagnostic(event)
  }

  func connectionDidInterrupt(_ connectionID: ObjectIdentifier) {
    handleDisconnect(for: connectionID, detail: "xpc-interrupted")
  }

  func connectionDidInvalidate(_ connectionID: ObjectIdentifier) {
    handleDisconnect(for: connectionID, detail: "xpc-invalidated")
  }

  private func handleDisconnect(for connectionID: ObjectIdentifier, detail: String) {
    guard let role = connectionRoles.removeValue(forKey: connectionID) else {
      return
    }

    switch role {
    case .app:
      if appConnectionID == connectionID {
        appObserver = nil
        appConnectionID = nil
      }
      statusSnapshot.update(endpoint: .app, state: .unknown, detail: detail, at: now())
    case .agent:
      if agentConnectionID == connectionID {
        agentPrompt = nil
        agentConnectionID = nil
      }
      if let presentedRequest {
        queuedRequests.insert(presentedRequest, at: 0)
        self.presentedRequest = nil
      }
      statusSnapshot.update(endpoint: .agent, state: .unavailable, detail: detail, at: now())
    }

    refreshPendingPromptCount()
    notifyAppObserver()
  }

  private func dispatchNextPromptIfPossible() {
    guard presentedRequest == nil, statusSnapshot.loginItemEnabled, let agentPrompt,
      !queuedRequests.isEmpty
    else {
      return
    }

    let nextRequest = queuedRequests.removeFirst()
    presentedRequest = nextRequest
    statusSnapshot.update(endpoint: .agent, state: .busy, detail: "prompt-presenting", at: now())
    agentPrompt.presentPrompt(nextRequest)
  }

  private func refreshPendingPromptCount() {
    statusSnapshot.pendingPromptCount = queuedRequests.count + (presentedRequest == nil ? 0 : 1)
  }

  private func notifyAppObserver() {
    appObserver?.statusDidChange(statusSnapshot)
  }
}

public enum AegisXPCContract {
  public static let appBundleIdentifier = "com.nanzhipro.AegisApp"
  public static let agentBundleIdentifier = "com.nanzhipro.AegisAgent"
  public static let extensionBundleIdentifier = "com.nanzhipro.AegisExtension"
  public static let extensionMachServiceSuffix = "com.nanzhipro.AegisExtension.xpc"

  public static func defaultTeamIdentifier(
    processInfo: ProcessInfo = .processInfo,
    bundle: Bundle = .main
  ) -> String? {
    let environmentKeys = ["AEGIS_TEAM_ID", "APPLE_TEAM_ID"]

    for key in environmentKeys {
      if let value = processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      {
        return value
      }
    }

    if let prefix = bundle.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String {
      let normalizedPrefix = prefix.replacingOccurrences(of: ".", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !normalizedPrefix.isEmpty {
        return normalizedPrefix
      }
    }

    return nil
  }

  public static func machServiceName(teamIdentifier: String? = defaultTeamIdentifier()) -> String {
    guard let teamIdentifier, !teamIdentifier.isEmpty else {
      return extensionMachServiceSuffix
    }

    return "\(teamIdentifier).\(extensionMachServiceSuffix)"
  }

  public static func extensionCodeSigningRequirement(
    teamIdentifier: String? = defaultTeamIdentifier()
  ) -> String {
    signingRequirement(
      teamIdentifier: teamIdentifier, bundleIdentifiers: [extensionBundleIdentifier])
  }

  public static func clientCodeSigningRequirement(
    teamIdentifier: String? = defaultTeamIdentifier()
  ) -> String {
    signingRequirement(
      teamIdentifier: teamIdentifier,
      bundleIdentifiers: [appBundleIdentifier, agentBundleIdentifier]
    )
  }

  private static func signingRequirement(
    teamIdentifier: String?,
    bundleIdentifiers: [String]
  ) -> String {
    let identifiers = bundleIdentifiers.map { "identifier \"\($0)\"" }.joined(separator: " or ")
    let identifierClause = "(\(identifiers))"

    guard let teamIdentifier, !teamIdentifier.isEmpty else {
      return identifierClause
    }

    return
      "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and \(identifierClause)"
  }
}

public enum AegisXPCConnectionMode {
  case machService(name: String)
  case listenerEndpoint(NSXPCListenerEndpoint)
}

@MainActor
public protocol AppIPCControlling: AnyObject {
  var onStatusDidChange: ((IPCStatusSnapshot) -> Void)? { get set }
  var onDiagnosticEvent: ((ExtensionDiagnosticEvent) -> Void)? { get set }

  func activate() async throws -> IPCStatusSnapshot
  func snapshot() async throws -> IPCStatusSnapshot
  func reloadPolicy() async throws -> IPCStatusSnapshot
  func setLoginItemEnabled(_ isEnabled: Bool) async throws -> IPCStatusSnapshot
}

@MainActor
public protocol AgentIPCControlling: AnyObject {
  var onPromptPresented: ((AccessPromptRequest) -> Void)? { get set }
  var onPromptCancelled: ((UUID) -> Void)? { get set }
  var onPolicyDidReload: ((IPCStatusSnapshot) -> Void)? { get set }

  func activate() async throws -> IPCStatusSnapshot
  func snapshot() async throws -> IPCStatusSnapshot
  func submitDecision(
    _ decision: AccessPromptDecision,
    for request: AccessPromptRequest
  ) async throws -> IPCStatusSnapshot
}

@MainActor
public final class FileBackedAppIPCController: AppIPCControlling {
  public var onStatusDidChange: ((IPCStatusSnapshot) -> Void)?
  public var onDiagnosticEvent: ((ExtensionDiagnosticEvent) -> Void)?

  private let service: AegisIPCService

  public init(service: AegisIPCService) {
    self.service = service
  }

  public convenience init(
    paths: SharedContainerPaths,
    policyStoreFileStore: LocalPolicyStoreFileStore? = nil
  ) {
    self.init(service: AegisIPCService(paths: paths, policyStoreFileStore: policyStoreFileStore))
  }

  public func activate() async throws -> IPCStatusSnapshot {
    let snapshot = try await service.publish(endpoint: .app, state: .ready, detail: "app-ready")
    onStatusDidChange?(snapshot)
    return snapshot
  }

  public func snapshot() async throws -> IPCStatusSnapshot {
    let snapshot = try await service.snapshot()
    onStatusDidChange?(snapshot)
    return snapshot
  }

  public func reloadPolicy() async throws -> IPCStatusSnapshot {
    let snapshot = try await service.reloadPolicy()
    onStatusDidChange?(snapshot)
    return snapshot
  }

  public func setLoginItemEnabled(_ isEnabled: Bool) async throws -> IPCStatusSnapshot {
    let snapshot = try await service.setLoginItemEnabled(isEnabled)
    onStatusDidChange?(snapshot)
    return snapshot
  }
}

@MainActor
public final class FileBackedAgentIPCController: AgentIPCControlling {
  public var onPromptPresented: ((AccessPromptRequest) -> Void)?
  public var onPromptCancelled: ((UUID) -> Void)?
  public var onPolicyDidReload: ((IPCStatusSnapshot) -> Void)?

  private let service: AegisIPCService

  public init(service: AegisIPCService) {
    self.service = service
  }

  public convenience init(
    paths: SharedContainerPaths,
    policyStoreFileStore: LocalPolicyStoreFileStore? = nil
  ) {
    self.init(service: AegisIPCService(paths: paths, policyStoreFileStore: policyStoreFileStore))
  }

  public func activate() async throws -> IPCStatusSnapshot {
    _ = try await service.publish(endpoint: .agent, state: .ready, detail: "agent-ready")
    if let request = try await service.claimNextPrompt() {
      onPromptPresented?(request)
    }
    return try await snapshot()
  }

  public func snapshot() async throws -> IPCStatusSnapshot {
    try await service.snapshot()
  }

  public func submitDecision(
    _ decision: AccessPromptDecision,
    for request: AccessPromptRequest
  ) async throws -> IPCStatusSnapshot {
    _ = try await service.submitDecision(decision, for: request)
    if let nextRequest = try await service.claimNextPrompt() {
      onPromptPresented?(nextRequest)
    }
    return try await snapshot()
  }
}

@MainActor
public final class AegisAppXPCController: NSObject, AppIPCControlling {
  public var onStatusDidChange: ((IPCStatusSnapshot) -> Void)? {
    didSet {
      observerBridge.statusHandler = onStatusDidChange
    }
  }

  public var onDiagnosticEvent: ((ExtensionDiagnosticEvent) -> Void)? {
    didSet {
      observerBridge.diagnosticHandler = onDiagnosticEvent
    }
  }

  private let connectionMode: AegisXPCConnectionMode
  private let codeSigningRequirement: String?
  private let observerBridge = AppObserverBridge()
  private var connection: NSXPCConnection?
  private var reconnecting = false

  public init(
    connectionMode: AegisXPCConnectionMode = .machService(
      name: AegisXPCContract.machServiceName()),
    codeSigningRequirement: String? = AegisXPCContract.extensionCodeSigningRequirement()
  ) {
    self.connectionMode = connectionMode
    self.codeSigningRequirement = codeSigningRequirement
    super.init()
  }

  public func activate() async throws -> IPCStatusSnapshot {
    let snapshot = try await publishClientReady(role: .app)
    onStatusDidChange?(snapshot)
    return snapshot
  }

  public func snapshot() async throws -> IPCStatusSnapshot {
    let snapshot = try await withSnapshotReply { proxy, reply in
      proxy.snapshot(withReply: reply)
    }
    onStatusDidChange?(snapshot)
    return snapshot
  }

  public func reloadPolicy() async throws -> IPCStatusSnapshot {
    let snapshot = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<IPCStatusSnapshot, Error>) in
      let connection = ensureConnection()
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          continuation.resume(throwing: error)
        }) as? AegisExtensionControlProtocol
      else {
        continuation.resume(throwing: IPCTransportError.storeFailure)
        return
      }

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

    onStatusDidChange?(snapshot)
    return snapshot
  }

  public func setLoginItemEnabled(_ isEnabled: Bool) async throws -> IPCStatusSnapshot {
    let snapshot = try await withSnapshotReply { proxy, reply in
      proxy.updateLoginItemEnabled(isEnabled, withReply: reply)
    }
    onStatusDidChange?(snapshot)
    return snapshot
  }

  private func publishClientReady(role: AegisXPCClientRole) async throws -> IPCStatusSnapshot {
    try await withSnapshotReply { proxy, reply in
      proxy.publishClientReady(role: role.rawValue, withReply: reply)
    }
  }

  private func withSnapshotReply(
    _ call: @escaping (AegisExtensionControlProtocol, @escaping (IPCStatusSnapshot) -> Void) -> Void
  ) async throws -> IPCStatusSnapshot {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<IPCStatusSnapshot, Error>) in
      let connection = ensureConnection()
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          continuation.resume(throwing: error)
        }) as? AegisExtensionControlProtocol
      else {
        continuation.resume(throwing: IPCTransportError.storeFailure)
        return
      }

      call(proxy) { snapshot in
        continuation.resume(returning: snapshot)
      }
    }
  }

  private func ensureConnection() -> NSXPCConnection {
    if let connection {
      return connection
    }

    let connection = makeConnection()
    connection.remoteObjectInterface = AegisXPCInterfaces.extensionControl()
    connection.exportedInterface = AegisXPCInterfaces.appObserver()
    connection.exportedObject = observerBridge
    if let codeSigningRequirement {
      connection.setCodeSigningRequirement(codeSigningRequirement)
    }
    connection.invalidationHandler = { [weak self] in
      Task { @MainActor [weak self] in
        self?.handleDisconnect()
      }
    }
    connection.interruptionHandler = { [weak self] in
      Task { @MainActor [weak self] in
        self?.handleDisconnect()
      }
    }
    connection.resume()
    self.connection = connection
    return connection
  }

  private func makeConnection() -> NSXPCConnection {
    switch connectionMode {
    case .machService(let name):
      return NSXPCConnection(machServiceName: name, options: [])
    case .listenerEndpoint(let endpoint):
      return NSXPCConnection(listenerEndpoint: endpoint)
    }
  }

  private func handleDisconnect() {
    connection = nil
    guard !reconnecting else {
      return
    }

    reconnecting = true
    Task { @MainActor [weak self] in
      defer { self?.reconnecting = false }
      _ = try? await self?.activate()
    }
  }
}

@MainActor
public final class AegisAgentXPCController: NSObject, AgentIPCControlling {
  public var onPromptPresented: ((AccessPromptRequest) -> Void)? {
    didSet {
      promptBridge.promptHandler = onPromptPresented
    }
  }

  public var onPromptCancelled: ((UUID) -> Void)? {
    didSet {
      promptBridge.cancelHandler = { [weak self] requestID in
        self?.currentRequestID = nil
        self?.onPromptCancelled?(requestID)
      }
    }
  }

  public var onPolicyDidReload: ((IPCStatusSnapshot) -> Void)? {
    didSet {
      promptBridge.reloadHandler = onPolicyDidReload
    }
  }

  private let connectionMode: AegisXPCConnectionMode
  private let codeSigningRequirement: String?
  private let promptBridge = AgentPromptBridge()
  private var connection: NSXPCConnection?
  private var reconnecting = false
  private var currentRequestID: UUID?

  public init(
    connectionMode: AegisXPCConnectionMode = .machService(
      name: AegisXPCContract.machServiceName()),
    codeSigningRequirement: String? = AegisXPCContract.extensionCodeSigningRequirement()
  ) {
    self.connectionMode = connectionMode
    self.codeSigningRequirement = codeSigningRequirement
    super.init()
    promptBridge.promptHandler = { [weak self] request in
      self?.currentRequestID = request.requestID
      self?.onPromptPresented?(request)
    }
  }

  public func activate() async throws -> IPCStatusSnapshot {
    try await publishClientReady(role: .agent)
  }

  public func snapshot() async throws -> IPCStatusSnapshot {
    try await withSnapshotReply { proxy, reply in
      proxy.snapshot(withReply: reply)
    }
  }

  public func submitDecision(
    _ decision: AccessPromptDecision,
    for request: AccessPromptRequest
  ) async throws -> IPCStatusSnapshot {
    guard decision.requestID == request.requestID else {
      throw IPCTransportError.invalidResponse
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let connection = ensureConnection()
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          continuation.resume(throwing: error)
        }) as? AegisExtensionControlProtocol
      else {
        continuation.resume(throwing: IPCTransportError.storeFailure)
        return
      }

      proxy.submitDecision(decision) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }

    currentRequestID = nil
    return try await snapshot()
  }

  private func publishClientReady(role: AegisXPCClientRole) async throws -> IPCStatusSnapshot {
    try await withSnapshotReply { proxy, reply in
      proxy.publishClientReady(role: role.rawValue, withReply: reply)
    }
  }

  private func withSnapshotReply(
    _ call: @escaping (AegisExtensionControlProtocol, @escaping (IPCStatusSnapshot) -> Void) -> Void
  ) async throws -> IPCStatusSnapshot {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<IPCStatusSnapshot, Error>) in
      let connection = ensureConnection()
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          continuation.resume(throwing: error)
        }) as? AegisExtensionControlProtocol
      else {
        continuation.resume(throwing: IPCTransportError.storeFailure)
        return
      }

      call(proxy) { snapshot in
        continuation.resume(returning: snapshot)
      }
    }
  }

  private func ensureConnection() -> NSXPCConnection {
    if let connection {
      return connection
    }

    let connection = makeConnection()
    connection.remoteObjectInterface = AegisXPCInterfaces.extensionControl()
    connection.exportedInterface = AegisXPCInterfaces.agentPrompt()
    connection.exportedObject = promptBridge
    if let codeSigningRequirement {
      connection.setCodeSigningRequirement(codeSigningRequirement)
    }
    connection.invalidationHandler = { [weak self] in
      Task { @MainActor [weak self] in
        self?.handleDisconnect()
      }
    }
    connection.interruptionHandler = { [weak self] in
      Task { @MainActor [weak self] in
        self?.handleDisconnect()
      }
    }
    connection.resume()
    self.connection = connection
    return connection
  }

  private func makeConnection() -> NSXPCConnection {
    switch connectionMode {
    case .machService(let name):
      return NSXPCConnection(machServiceName: name, options: [])
    case .listenerEndpoint(let endpoint):
      return NSXPCConnection(listenerEndpoint: endpoint)
    }
  }

  private func handleDisconnect() {
    connection = nil

    if let currentRequestID {
      onPromptCancelled?(currentRequestID)
      self.currentRequestID = nil
    }

    guard !reconnecting else {
      return
    }

    reconnecting = true
    Task { @MainActor [weak self] in
      defer { self?.reconnecting = false }
      _ = try? await self?.activate()
    }
  }
}

private final class AppObserverBridge: NSObject, AegisAppObserverProtocol {
  var statusHandler: ((IPCStatusSnapshot) -> Void)?
  var diagnosticHandler: ((ExtensionDiagnosticEvent) -> Void)?

  func statusDidChange(_ snapshot: IPCStatusSnapshot) {
    statusHandler?(snapshot)
  }

  func extensionDidEmitDiagnostic(_ event: ExtensionDiagnosticEvent) {
    diagnosticHandler?(event)
  }
}

private final class AgentPromptBridge: NSObject, AegisAgentPromptProtocol {
  var promptHandler: ((AccessPromptRequest) -> Void)?
  var cancelHandler: ((UUID) -> Void)?
  var reloadHandler: ((IPCStatusSnapshot) -> Void)?

  func presentPrompt(_ request: AccessPromptRequest) {
    promptHandler?(request)
  }

  func cancelPrompt(requestID: NSUUID) {
    cancelHandler?(requestID as UUID)
  }

  func policyDidReload(_ snapshot: IPCStatusSnapshot) {
    reloadHandler?(snapshot)
  }
}
