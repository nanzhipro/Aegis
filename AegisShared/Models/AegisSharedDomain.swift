import Foundation

public enum SharedPolicyDefaults {
  public static let promptTimeoutSeconds: TimeInterval = 5
  public static let protectedWorkspaceTemplates: [(name: String, relativePath: String)] = [
    (name: "OpenClaw", relativePath: "~/OpenClaw"),
    (name: "HermesAgentWorkspace", relativePath: "~/HermesAgentWorkspace"),
  ]
  public static let localPolicyStoreFileName = "LocalPolicyStore.json"
}

public enum AccessEventType {
  public static let authOpen = "AUTH_OPEN"
}

enum AegisSecureCodingBridge {
  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  static func encode<T: Encodable>(_ value: T) -> Data? {
    try? encoder().encode(value)
  }

  static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
    guard let data else {
      return nil
    }

    return try? decoder().decode(type, from: data)
  }
}

public struct ProtectedWorkspace: Codable, Identifiable, Hashable, Sendable {
  public let id: UUID
  public var name: String
  public var path: String
  public var isEnabled: Bool

  public init(id: UUID, name: String, path: String, isEnabled: Bool) {
    self.id = id
    self.name = name
    self.path = path
    self.isEnabled = isEnabled
  }

  public func normalizedPath(using normalizer: PathNormalizer = PathNormalizer()) -> String {
    normalizer.normalize(path)
  }

  public func matches(targetPath: String, using normalizer: PathNormalizer = PathNormalizer())
    -> Bool
  {
    let workspacePath = normalizedPath(using: normalizer)
    let candidatePath = normalizer.normalize(targetPath)

    guard !workspacePath.isEmpty, !candidatePath.isEmpty else {
      return false
    }

    return candidatePath == workspacePath || candidatePath.hasPrefix(workspacePath + "/")
  }

  public static func defaultWorkspaces(
    homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> [ProtectedWorkspace] {
    let normalizer = PathNormalizer(homeDirectoryURL: homeDirectoryURL)

    return SharedPolicyDefaults.protectedWorkspaceTemplates.map { template in
      ProtectedWorkspace(
        id: UUID(),
        name: template.name,
        path: normalizer.normalize(template.relativePath),
        isEnabled: true
      )
    }
  }
}

public enum AccessDecision: String, Codable, Hashable, Sendable, CaseIterable {
  case allow
  case deny
}

public enum DecisionSource: String, Codable, Hashable, Sendable, CaseIterable {
  case user
  case timeoutFallback
  case agentUnavailable
  case invalidResponse
  case trustedProcessPolicy
  case rememberedRule
  case appleSignedDefaultAllow
  case unprotectedPath
}

public struct PolicySettings: Codable, Hashable, Sendable {
  public var defaultTimeoutDecision: AccessDecision
  public var workspaces: [ProtectedWorkspace]

  public init(defaultTimeoutDecision: AccessDecision, workspaces: [ProtectedWorkspace]) {
    self.defaultTimeoutDecision = defaultTimeoutDecision
    self.workspaces = workspaces
  }

  public static func defaultSettings(
    homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> PolicySettings {
    PolicySettings(
      defaultTimeoutDecision: .deny,
      workspaces: ProtectedWorkspace.defaultWorkspaces(homeDirectoryURL: homeDirectoryURL)
    )
  }
}

public struct ProcessIdentityFingerprint: Codable, Hashable, Sendable {
  public let signingIdentifier: String?
  public let teamIdentifier: String?
  public let executablePath: String
  public let isAppleSigned: Bool

  public init(
    signingIdentifier: String?, teamIdentifier: String?, executablePath: String, isAppleSigned: Bool
  ) {
    self.signingIdentifier = signingIdentifier
    self.teamIdentifier = teamIdentifier
    self.executablePath = executablePath
    self.isAppleSigned = isAppleSigned
  }

  public static func from(request: AccessPromptRequest) -> ProcessIdentityFingerprint {
    ProcessIdentityFingerprint(
      signingIdentifier: request.signingIdentifier,
      teamIdentifier: request.teamIdentifier,
      executablePath: request.processPath,
      isAppleSigned: request.isAppleSigned
    )
  }
}

public struct RememberedDecisionRule: Codable, Identifiable, Hashable, Sendable {
  public let id: UUID
  public let workspaceID: UUID
  public let process: ProcessIdentityFingerprint
  public var decision: AccessDecision
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID, workspaceID: UUID, process: ProcessIdentityFingerprint, decision: AccessDecision,
    createdAt: Date, updatedAt: Date
  ) {
    self.id = id
    self.workspaceID = workspaceID
    self.process = process
    self.decision = decision
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public func matches(request: AccessPromptRequest) -> Bool {
    guard request.eventType == AccessEventType.authOpen else {
      return false
    }

    guard !request.isAppleSigned else {
      return false
    }

    return workspaceID == request.workspaceID && process == .from(request: request)
  }
}

public final class LocalPolicyStore: NSObject, NSSecureCoding, Codable, @unchecked Sendable {
  public var settings: PolicySettings
  public var rememberedRules: [RememberedDecisionRule]

  public init(settings: PolicySettings, rememberedRules: [RememberedDecisionRule]) {
    self.settings = settings
    self.rememberedRules = rememberedRules
  }

  public static var supportsSecureCoding: Bool {
    true
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? LocalPolicyStore else {
      return false
    }

    return settings == object.settings && rememberedRules == object.rememberedRules
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(settings)
    hasher.combine(rememberedRules)
    return hasher.finalize()
  }

  public required convenience init?(coder: NSCoder) {
    guard
      let settings = AegisSecureCodingBridge.decode(
        PolicySettings.self,
        from: coder.decodeObject(of: NSData.self, forKey: "settings") as Data?),
      let rememberedRules = AegisSecureCodingBridge.decode(
        [RememberedDecisionRule].self,
        from: coder.decodeObject(of: NSData.self, forKey: "rememberedRules") as Data?)
    else {
      return nil
    }

    self.init(settings: settings, rememberedRules: rememberedRules)
  }

  public func encode(with coder: NSCoder) {
    coder.encode(AegisSecureCodingBridge.encode(settings) as NSData?, forKey: "settings")
    coder.encode(
      AegisSecureCodingBridge.encode(rememberedRules) as NSData?,
      forKey: "rememberedRules"
    )
  }

  enum CodingKeys: String, CodingKey {
    case settings
    case rememberedRules
  }

  public required convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      settings: try container.decode(PolicySettings.self, forKey: .settings),
      rememberedRules: try container.decode([RememberedDecisionRule].self, forKey: .rememberedRules)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(settings, forKey: .settings)
    try container.encode(rememberedRules, forKey: .rememberedRules)
  }

  public static func defaultStore(
    homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> LocalPolicyStore {
    LocalPolicyStore(
      settings: .defaultSettings(homeDirectoryURL: homeDirectoryURL), rememberedRules: [])
  }

  public func rememberedDecision(for request: AccessPromptRequest) -> RememberedDecisionRule? {
    rememberedRules.last(where: { $0.matches(request: request) })
  }

  public func applyRememberedDecision(
    _ decision: AccessPromptDecision, for request: AccessPromptRequest, at timestamp: Date = Date()
  ) {
    guard decision.rememberChoice else {
      return
    }

    guard request.eventType == AccessEventType.authOpen else {
      return
    }

    guard !request.isAppleSigned else {
      return
    }

    let fingerprint = ProcessIdentityFingerprint.from(request: request)

    if let existingIndex = rememberedRules.lastIndex(where: {
      $0.workspaceID == request.workspaceID && $0.process == fingerprint
    }) {
      rememberedRules[existingIndex].decision = decision.decision
      rememberedRules[existingIndex].updatedAt = timestamp
      return
    }

    rememberedRules.append(
      RememberedDecisionRule(
        id: UUID(),
        workspaceID: request.workspaceID,
        process: fingerprint,
        decision: decision.decision,
        createdAt: timestamp,
        updatedAt: timestamp
      )
    )
  }

  public func clearRememberedDecisions(workspaceID: UUID? = nil) {
    guard let workspaceID else {
      rememberedRules.removeAll()
      return
    }

    rememberedRules.removeAll { $0.workspaceID == workspaceID }
  }
}

public final class AccessPromptRequest: NSObject, NSSecureCoding, Codable, @unchecked Sendable {
  public let requestID: UUID
  public let eventType: String
  public let targetPath: String
  public let workspaceID: UUID
  public let workspaceName: String
  public let processPath: String
  public let pid: Int32
  public let signingIdentifier: String?
  public let teamIdentifier: String?
  public let isAppleSigned: Bool
  public let deadline: Date

  public init(
    requestID: UUID,
    eventType: String,
    targetPath: String,
    workspaceID: UUID,
    workspaceName: String,
    processPath: String,
    pid: Int32,
    signingIdentifier: String?,
    teamIdentifier: String?,
    isAppleSigned: Bool,
    deadline: Date
  ) {
    self.requestID = requestID
    self.eventType = eventType
    self.targetPath = targetPath
    self.workspaceID = workspaceID
    self.workspaceName = workspaceName
    self.processPath = processPath
    self.pid = pid
    self.signingIdentifier = signingIdentifier
    self.teamIdentifier = teamIdentifier
    self.isAppleSigned = isAppleSigned
    self.deadline = deadline
  }

  public static var supportsSecureCoding: Bool {
    true
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? AccessPromptRequest else {
      return false
    }

    return requestID == object.requestID
      && eventType == object.eventType
      && targetPath == object.targetPath
      && workspaceID == object.workspaceID
      && workspaceName == object.workspaceName
      && processPath == object.processPath
      && pid == object.pid
      && signingIdentifier == object.signingIdentifier
      && teamIdentifier == object.teamIdentifier
      && isAppleSigned == object.isAppleSigned
      && deadline == object.deadline
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(requestID)
    hasher.combine(eventType)
    hasher.combine(targetPath)
    hasher.combine(workspaceID)
    hasher.combine(workspaceName)
    hasher.combine(processPath)
    hasher.combine(pid)
    hasher.combine(signingIdentifier)
    hasher.combine(teamIdentifier)
    hasher.combine(isAppleSigned)
    hasher.combine(deadline)
    return hasher.finalize()
  }

  public required convenience init?(coder: NSCoder) {
    guard
      let requestID = coder.decodeObject(of: NSUUID.self, forKey: "requestID") as UUID?,
      let eventType = coder.decodeObject(of: NSString.self, forKey: "eventType") as String?,
      let targetPath = coder.decodeObject(of: NSString.self, forKey: "targetPath") as String?,
      let workspaceID = coder.decodeObject(of: NSUUID.self, forKey: "workspaceID") as UUID?,
      let workspaceName = coder.decodeObject(of: NSString.self, forKey: "workspaceName") as String?,
      let processPath = coder.decodeObject(of: NSString.self, forKey: "processPath") as String?,
      let deadline = coder.decodeObject(of: NSDate.self, forKey: "deadline") as Date?
    else {
      return nil
    }

    self.init(
      requestID: requestID,
      eventType: eventType,
      targetPath: targetPath,
      workspaceID: workspaceID,
      workspaceName: workspaceName,
      processPath: processPath,
      pid: Int32(coder.decodeInt64(forKey: "pid")),
      signingIdentifier: coder.decodeObject(of: NSString.self, forKey: "signingIdentifier")
        as String?,
      teamIdentifier: coder.decodeObject(of: NSString.self, forKey: "teamIdentifier") as String?,
      isAppleSigned: coder.decodeBool(forKey: "isAppleSigned"),
      deadline: deadline
    )
  }

  public func encode(with coder: NSCoder) {
    coder.encode(requestID as NSUUID, forKey: "requestID")
    coder.encode(eventType as NSString, forKey: "eventType")
    coder.encode(targetPath as NSString, forKey: "targetPath")
    coder.encode(workspaceID as NSUUID, forKey: "workspaceID")
    coder.encode(workspaceName as NSString, forKey: "workspaceName")
    coder.encode(processPath as NSString, forKey: "processPath")
    coder.encode(Int(pid), forKey: "pid")
    coder.encode(signingIdentifier as NSString?, forKey: "signingIdentifier")
    coder.encode(teamIdentifier as NSString?, forKey: "teamIdentifier")
    coder.encode(isAppleSigned, forKey: "isAppleSigned")
    coder.encode(deadline as NSDate, forKey: "deadline")
  }

  enum CodingKeys: String, CodingKey {
    case requestID
    case eventType
    case targetPath
    case workspaceID
    case workspaceName
    case processPath
    case pid
    case signingIdentifier
    case teamIdentifier
    case isAppleSigned
    case deadline
  }

  public required convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      requestID: try container.decode(UUID.self, forKey: .requestID),
      eventType: try container.decode(String.self, forKey: .eventType),
      targetPath: try container.decode(String.self, forKey: .targetPath),
      workspaceID: try container.decode(UUID.self, forKey: .workspaceID),
      workspaceName: try container.decode(String.self, forKey: .workspaceName),
      processPath: try container.decode(String.self, forKey: .processPath),
      pid: try container.decode(Int32.self, forKey: .pid),
      signingIdentifier: try container.decodeIfPresent(String.self, forKey: .signingIdentifier),
      teamIdentifier: try container.decodeIfPresent(String.self, forKey: .teamIdentifier),
      isAppleSigned: try container.decode(Bool.self, forKey: .isAppleSigned),
      deadline: try container.decode(Date.self, forKey: .deadline)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(requestID, forKey: .requestID)
    try container.encode(eventType, forKey: .eventType)
    try container.encode(targetPath, forKey: .targetPath)
    try container.encode(workspaceID, forKey: .workspaceID)
    try container.encode(workspaceName, forKey: .workspaceName)
    try container.encode(processPath, forKey: .processPath)
    try container.encode(pid, forKey: .pid)
    try container.encodeIfPresent(signingIdentifier, forKey: .signingIdentifier)
    try container.encodeIfPresent(teamIdentifier, forKey: .teamIdentifier)
    try container.encode(isAppleSigned, forKey: .isAppleSigned)
    try container.encode(deadline, forKey: .deadline)
  }
}

public final class AccessPromptDecision: NSObject, NSSecureCoding, Codable, @unchecked Sendable {
  public let requestID: UUID
  public let decision: AccessDecision
  public let source: DecisionSource
  public let rememberChoice: Bool
  public let respondedAt: Date

  public init(
    requestID: UUID, decision: AccessDecision, source: DecisionSource, rememberChoice: Bool,
    respondedAt: Date
  ) {
    self.requestID = requestID
    self.decision = decision
    self.source = source
    self.rememberChoice = rememberChoice
    self.respondedAt = respondedAt
  }

  public static var supportsSecureCoding: Bool {
    true
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let object = object as? AccessPromptDecision else {
      return false
    }

    return requestID == object.requestID
      && decision == object.decision
      && source == object.source
      && rememberChoice == object.rememberChoice
      && respondedAt == object.respondedAt
  }

  public override var hash: Int {
    var hasher = Hasher()
    hasher.combine(requestID)
    hasher.combine(decision)
    hasher.combine(source)
    hasher.combine(rememberChoice)
    hasher.combine(respondedAt)
    return hasher.finalize()
  }

  public required convenience init?(coder: NSCoder) {
    guard
      let requestID = coder.decodeObject(of: NSUUID.self, forKey: "requestID") as UUID?,
      let decisionRawValue = coder.decodeObject(of: NSString.self, forKey: "decision") as String?,
      let decision = AccessDecision(rawValue: decisionRawValue),
      let sourceRawValue = coder.decodeObject(of: NSString.self, forKey: "source") as String?,
      let source = DecisionSource(rawValue: sourceRawValue),
      let respondedAt = coder.decodeObject(of: NSDate.self, forKey: "respondedAt") as Date?
    else {
      return nil
    }

    self.init(
      requestID: requestID,
      decision: decision,
      source: source,
      rememberChoice: coder.decodeBool(forKey: "rememberChoice"),
      respondedAt: respondedAt
    )
  }

  public func encode(with coder: NSCoder) {
    coder.encode(requestID as NSUUID, forKey: "requestID")
    coder.encode(decision.rawValue as NSString, forKey: "decision")
    coder.encode(source.rawValue as NSString, forKey: "source")
    coder.encode(rememberChoice, forKey: "rememberChoice")
    coder.encode(respondedAt as NSDate, forKey: "respondedAt")
  }

  enum CodingKeys: String, CodingKey {
    case requestID
    case decision
    case source
    case rememberChoice
    case respondedAt
  }

  public required convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      requestID: try container.decode(UUID.self, forKey: .requestID),
      decision: try container.decode(AccessDecision.self, forKey: .decision),
      source: try container.decode(DecisionSource.self, forKey: .source),
      rememberChoice: try container.decode(Bool.self, forKey: .rememberChoice),
      respondedAt: try container.decode(Date.self, forKey: .respondedAt)
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(requestID, forKey: .requestID)
    try container.encode(decision, forKey: .decision)
    try container.encode(source, forKey: .source)
    try container.encode(rememberChoice, forKey: .rememberChoice)
    try container.encode(respondedAt, forKey: .respondedAt)
  }
}

public struct ComponentStatus: Codable, Hashable, Sendable {
  public enum State: String, Codable, Hashable, Sendable, CaseIterable {
    case unknown
    case ready
    case needsAttention
    case unavailable
  }

  public struct Indicator: Codable, Hashable, Sendable {
    public var state: State
    public var detail: String?

    public init(state: State, detail: String? = nil) {
      self.state = state
      self.detail = detail
    }
  }

  public var systemExtension: Indicator
  public var loginItem: Indicator
  public var policy: Indicator
  public var protectionReadiness: Indicator

  public init(
    systemExtension: Indicator, loginItem: Indicator, policy: Indicator,
    protectionReadiness: Indicator
  ) {
    self.systemExtension = systemExtension
    self.loginItem = loginItem
    self.policy = policy
    self.protectionReadiness = protectionReadiness
  }

  public static let unknown = ComponentStatus(
    systemExtension: Indicator(state: .unknown),
    loginItem: Indicator(state: .unknown),
    policy: Indicator(state: .unknown),
    protectionReadiness: Indicator(state: .unknown)
  )
}

public struct PathNormalizer: Hashable, Sendable {
  public let homeDirectoryURL: URL

  public init(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
    self.homeDirectoryURL = homeDirectoryURL
  }

  public func normalize(_ rawPath: String) -> String {
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return ""
    }

    let expandedPath = expandTilde(in: trimmed)
    let standardizedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    let resolvedPath = URL(fileURLWithPath: standardizedPath).resolvingSymlinksInPath().path

    return removeTrailingSlash(from: resolvedPath)
  }

  private func expandTilde(in path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else {
      return path
    }

    if path == "~" {
      return homeDirectoryURL.path
    }

    return homeDirectoryURL.appendingPathComponent(String(path.dropFirst(2))).path
  }

  private func removeTrailingSlash(from path: String) -> String {
    guard path.count > 1 else {
      return path
    }

    var normalizedPath = path
    while normalizedPath.count > 1 && normalizedPath.hasSuffix("/") {
      normalizedPath.removeLast()
    }

    return normalizedPath
  }
}

public struct LocalPolicyStoreCodec: Sendable {
  public init() {}

  public func encode(_ store: LocalPolicyStore) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(store)
  }

  public func decode(_ data: Data) throws -> LocalPolicyStore {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(LocalPolicyStore.self, from: data)
  }
}

public actor LocalPolicyStoreFileStore {
  public let fileURL: URL
  private let codec: LocalPolicyStoreCodec

  public init(fileURL: URL, codec: LocalPolicyStoreCodec = LocalPolicyStoreCodec()) {
    self.fileURL = fileURL
    self.codec = codec
  }

  public func load(defaultingTo defaultStore: LocalPolicyStore = LocalPolicyStore.defaultStore())
    throws -> LocalPolicyStore
  {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return defaultStore
    }

    return try codec.decode(Data(contentsOf: fileURL))
  }

  public func save(_ store: LocalPolicyStore) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
    try codec.encode(store).write(to: fileURL, options: [.atomic])
  }
}
