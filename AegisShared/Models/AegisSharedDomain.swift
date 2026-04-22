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

public struct LocalPolicyStore: Codable, Hashable, Sendable {
  public var settings: PolicySettings
  public var rememberedRules: [RememberedDecisionRule]

  public init(settings: PolicySettings, rememberedRules: [RememberedDecisionRule]) {
    self.settings = settings
    self.rememberedRules = rememberedRules
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

  public mutating func applyRememberedDecision(
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

  public mutating func clearRememberedDecisions(workspaceID: UUID? = nil) {
    guard let workspaceID else {
      rememberedRules.removeAll()
      return
    }

    rememberedRules.removeAll { $0.workspaceID == workspaceID }
  }
}

public struct AccessPromptRequest: Codable, Hashable, Sendable {
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
}

public struct AccessPromptDecision: Codable, Hashable, Sendable {
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
