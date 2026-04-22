import Darwin
import EndpointSecurity
import Foundation
import OSLog

public struct AuthOpenEventHandler: Sendable {
  private let decisionEngine: ExtensionDecisionEngine

  public init(decisionEngine: ExtensionDecisionEngine) {
    self.decisionEngine = decisionEngine
  }

  public func activate() async throws -> IPCStatusSnapshot {
    try await decisionEngine.activate()
  }

  public func handle(_ request: AccessPromptRequest) async -> AccessPromptDecision {
    await decisionEngine.handleAuthOpen(request)
  }
}

public protocol EndpointSecurityClient: Sendable {
  func start() async throws
  func stop() async
  func handleAuthOpen(_ request: AccessPromptRequest) async -> AccessPromptDecision
}

public struct ExtensionActivationCoordinator: Sendable {
  private let transport: any ExtensionDecisionTransport
  private let authOpenHandler: AuthOpenEventHandler
  private let endpointSecurityClient: any EndpointSecurityClient

  public init(
    transport: any ExtensionDecisionTransport,
    authOpenHandler: AuthOpenEventHandler,
    endpointSecurityClient: any EndpointSecurityClient
  ) {
    self.transport = transport
    self.authOpenHandler = authOpenHandler
    self.endpointSecurityClient = endpointSecurityClient
  }

  public func activate() async throws -> IPCStatusSnapshot {
    await transport.startServing()
    _ = try await transport.publishExtensionStatus(
      state: .busy,
      detail: "endpoint-security-subscribing"
    )

    do {
      try await endpointSecurityClient.start()
      return try await authOpenHandler.activate()
    } catch {
      await endpointSecurityClient.stop()

      let diagnostic = extensionActivationDiagnostic(for: error)
      await transport.emitDiagnostic(diagnostic)
      _ = try? await transport.publishExtensionStatus(
        state: .unavailable,
        detail: diagnostic.metadata["detail"] ?? diagnostic.messageKey
      )
      throw error
    }
  }
}

public enum EndpointSecurityClientError: String, Error, Sendable {
  case invalidArgument
  case internalFailure
  case notEntitled
  case notPermitted
  case notPrivileged
  case tooManyClients
  case subscriptionFailed
  case messageConversionFailed
  case responseFailed

  var snapshotDetail: String {
    switch self {
    case .invalidArgument:
      return "es-client-invalid-argument"
    case .internalFailure:
      return "es-client-internal-failure"
    case .notEntitled:
      return "es-client-not-entitled"
    case .notPermitted:
      return "es-client-not-permitted"
    case .notPrivileged:
      return "es-client-not-privileged"
    case .tooManyClients:
      return "es-client-too-many-clients"
    case .subscriptionFailed:
      return "es-client-subscription-failed"
    case .messageConversionFailed:
      return "es-client-message-conversion-failed"
    case .responseFailed:
      return "es-client-response-failed"
    }
  }

  var diagnosticMessageKey: String {
    switch self {
    case .invalidArgument:
      return "aegis.extension.endpoint-security.invalid-argument"
    case .internalFailure:
      return "aegis.extension.endpoint-security.internal-failure"
    case .notEntitled:
      return "aegis.extension.endpoint-security.not-entitled"
    case .notPermitted:
      return "aegis.extension.endpoint-security.not-permitted"
    case .notPrivileged:
      return "aegis.extension.endpoint-security.not-privileged"
    case .tooManyClients:
      return "aegis.extension.endpoint-security.too-many-clients"
    case .subscriptionFailed:
      return "aegis.extension.endpoint-security.subscription-failed"
    case .messageConversionFailed:
      return "aegis.extension.endpoint-security.message-conversion-failed"
    case .responseFailed:
      return "aegis.extension.endpoint-security.response-failed"
    }
  }

  func diagnosticEvent(metadata: [String: String] = [:]) -> ExtensionDiagnosticEvent {
    var mergedMetadata = metadata
    mergedMetadata["detail"] = snapshotDetail
    mergedMetadata["code"] = rawValue
    return ExtensionDiagnosticEvent(messageKey: diagnosticMessageKey, metadata: mergedMetadata)
  }
}

private func extensionActivationDiagnostic(for error: Error) -> ExtensionDiagnosticEvent {
  guard let error = error as? EndpointSecurityClientError else {
    return ExtensionDiagnosticEvent(
      messageKey: "aegis.extension.endpoint-security.unexpected-failure",
      metadata: ["detail": "es-client-unexpected-failure"]
    )
  }

  return error.diagnosticEvent()
}

public final class LiveEndpointSecurityClient: EndpointSecurityClient, @unchecked Sendable {
  private let authOpenHandler: AuthOpenEventHandler
  private let logger = Logger(
    subsystem: "com.nanzhipro.AegisExtension",
    category: "EndpointSecurityClient"
  )
  private let clientState = EndpointSecurityClientState()

  public init(authOpenHandler: AuthOpenEventHandler) {
    self.authOpenHandler = authOpenHandler
  }

  public func start() async throws {
    let existingClient = await clientState.loadRawValue()

    guard existingClient == nil else {
      return
    }

    var newClient: OpaquePointer?
    let result = es_new_client(&newClient) { [weak self] client, message in
      guard let self else {
        _ = es_respond_auth_result(client, message, ES_AUTH_RESULT_DENY, false)
        return
      }

      self.processAuthOpenMessage(client: client, message: message)
    }

    guard result == ES_NEW_CLIENT_RESULT_SUCCESS, let newClient else {
      throw Self.mapNewClientResult(result)
    }

    var subscriptions: [es_event_type_t] = [ES_EVENT_TYPE_AUTH_OPEN]
    let subscribeResult = subscriptions.withUnsafeMutableBufferPointer { buffer in
      es_subscribe(newClient, buffer.baseAddress!, 1)
    }
    guard subscribeResult == ES_RETURN_SUCCESS else {
      es_delete_client(newClient)
      throw EndpointSecurityClientError.subscriptionFailed
    }

    await clientState.storeRawValue(Int(bitPattern: newClient))
  }

  public func stop() async {
    let rawValue = await clientState.takeRawValue()
    let client = rawValue.flatMap(OpaquePointer.init(bitPattern:))

    guard let client else {
      return
    }

    es_delete_client(client)
  }

  public func handleAuthOpen(_ request: AccessPromptRequest) async -> AccessPromptDecision {
    await authOpenHandler.handle(request)
  }

  private func processAuthOpenMessage(client: OpaquePointer?, message: UnsafePointer<es_message_t>)
  {
    guard message.pointee.event_type == ES_EVENT_TYPE_AUTH_OPEN else {
      return
    }

    guard let request = makeRequest(from: message) else {
      logger.error("Dropping AUTH_OPEN event because request conversion failed.")
      respond(.deny, client: client, message: message)
      return
    }

    let timeout = max(0, request.deadline.timeIntervalSinceNow)
    let semaphore = DispatchSemaphore(value: 0)
    let decisionBox = LockedDecisionBox()
    let decisionTask = Task { [authOpenHandler] in
      let decision = await authOpenHandler.handle(request)

      guard !Task.isCancelled else {
        return
      }

      decisionBox.store(decision)
      semaphore.signal()
    }

    let waitResult = semaphore.wait(timeout: .now() + timeout)
    let decision: AccessDecision

    switch waitResult {
    case .success:
      decision = decisionBox.load()?.decision ?? .deny
    case .timedOut:
      decisionTask.cancel()
      decision = .deny
      logger.error(
        "AUTH_OPEN processing exceeded the local deadline before the ES response was ready."
      )
    }

    respond(decision, client: client, message: message)
  }

  private func respond(
    _ decision: AccessDecision,
    client: OpaquePointer?,
    message: UnsafePointer<es_message_t>
  ) {
    guard let client else {
      logger.error("Unable to respond to AUTH_OPEN because the ES client pointer was missing.")
      return
    }

    let authResult: es_auth_result_t =
      decision == .allow ? ES_AUTH_RESULT_ALLOW : ES_AUTH_RESULT_DENY
    let responseResult = es_respond_auth_result(client, message, authResult, false)

    guard responseResult == ES_RESPOND_RESULT_SUCCESS else {
      logger.error(
        "es_respond_auth_result failed with result=\(String(describing: responseResult), privacy: .public)."
      )
      return
    }
  }

  private func makeRequest(from message: UnsafePointer<es_message_t>) -> AccessPromptRequest? {
    let process = message.pointee.process.pointee
    let openEvent = message.pointee.event.open

    guard
      let targetPath = string(from: openEvent.file.pointee.path),
      let processPath = string(from: process.executable.pointee.path)
    else {
      return nil
    }

    let teamIdentifier = string(from: process.team_id)
    let workspaceURL = URL(fileURLWithPath: targetPath, isDirectory: false)
      .deletingLastPathComponent()
    let remainingKernelTime = remainingKernelDeadlineSeconds(
      messageDeadline: message.pointee.deadline)
    let clampedTimeout = max(
      0,
      min(SharedPolicyDefaults.promptTimeoutSeconds, remainingKernelTime - 0.25)
    )

    return AccessPromptRequest(
      requestID: UUID(),
      eventType: AccessEventType.authOpen,
      targetPath: targetPath,
      workspaceID: UUID(),
      workspaceName: workspaceURL.lastPathComponent,
      processPath: processPath,
      pid: 0,
      signingIdentifier: string(from: process.signing_id),
      teamIdentifier: teamIdentifier,
      isAppleSigned: process.is_platform_binary || teamIdentifier == "APPLE",
      deadline: Date().addingTimeInterval(clampedTimeout)
    )
  }

  private func string(from token: es_string_token_t) -> String? {
    guard token.length > 0, let data = token.data else {
      return nil
    }

    let bytes = UnsafeRawPointer(data).assumingMemoryBound(to: UInt8.self)
    let buffer = UnsafeBufferPointer(start: bytes, count: Int(token.length))
    return String(decoding: buffer, as: UTF8.self)
  }

  private func remainingKernelDeadlineSeconds(messageDeadline: UInt64) -> TimeInterval {
    let now = mach_absolute_time()

    guard messageDeadline > now else {
      return 0
    }

    var timebaseInfo = mach_timebase_info_data_t()
    mach_timebase_info(&timebaseInfo)

    let delta = messageDeadline - now
    let nanoseconds = Double(delta) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
    return nanoseconds / 1_000_000_000
  }

  private static func mapNewClientResult(_ result: es_new_client_result_t)
    -> EndpointSecurityClientError
  {
    switch result {
    case ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT:
      return .invalidArgument
    case ES_NEW_CLIENT_RESULT_ERR_INTERNAL:
      return .internalFailure
    case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
      return .notEntitled
    case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
      return .notPermitted
    case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
      return .notPrivileged
    case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS:
      return .tooManyClients
    default:
      return .internalFailure
    }
  }
}

private final class LockedDecisionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var decision: AccessPromptDecision?

  func store(_ decision: AccessPromptDecision) {
    lock.lock()
    self.decision = decision
    lock.unlock()
  }

  func load() -> AccessPromptDecision? {
    lock.lock()
    defer { lock.unlock() }
    return decision
  }
}

private actor EndpointSecurityClientState {
  private var rawValue: Int?

  func loadRawValue() -> Int? {
    rawValue
  }

  func storeRawValue(_ rawValue: Int?) {
    self.rawValue = rawValue
  }

  func takeRawValue() -> Int? {
    defer { rawValue = nil }
    return rawValue
  }
}
