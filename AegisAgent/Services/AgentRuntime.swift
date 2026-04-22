import Foundation
import Observation

@MainActor
@Observable
final class AgentRuntime {
  struct Configuration {
    var sharedContainerPaths: SharedContainerPaths
    var now: @Sendable () -> Date

    init(
      sharedContainerPaths: SharedContainerPaths = .defaultRoot(),
      now: @escaping @Sendable () -> Date = { Date() }
    ) {
      self.sharedContainerPaths = sharedContainerPaths
      self.now = now
    }

    static func live() -> Configuration {
      Configuration()
    }
  }

  private let service: AegisIPCService
  private let now: @Sendable () -> Date

  private(set) var statusSnapshot: IPCStatusSnapshot
  private(set) var currentRequest: AccessPromptRequest?
  private(set) var lastDecision: AccessPromptDecision?
  private(set) var lastError: IPCTransportError?
  var rememberChoice = false

  init(configuration: Configuration = .live(), service: AegisIPCService? = nil) {
    let sharedService = service ?? AegisIPCService(paths: configuration.sharedContainerPaths)
    self.service = sharedService
    self.now = configuration.now
    self.statusSnapshot = .empty(now: configuration.now())
  }

  var agentStatusKey: String {
    switch statusSnapshot.agent.state {
    case .ready:
      return "aegis.agent.status.ready"
    case .busy:
      return "aegis.agent.status.busy"
    case .unavailable:
      return "aegis.agent.status.unavailable"
    case .unknown:
      return "aegis.agent.status.unknown"
    }
  }

  var pendingPromptCount: Int {
    statusSnapshot.pendingPromptCount + (currentRequest == nil ? 0 : 1)
  }

  func activate() async {
    do {
      statusSnapshot = try await service.publish(
        endpoint: .agent, state: .ready, detail: "agent-ready", at: now())
      lastError = nil
      if currentRequest == nil {
        currentRequest = try await service.claimNextPrompt(at: now())
      }
      statusSnapshot = try await service.snapshot()
    } catch let error as IPCTransportError {
      lastError = error
    } catch {
      lastError = .storeFailure
    }
  }

  func refresh() async {
    await activate()
  }

  func allowCurrentPrompt() async {
    await submitCurrentPrompt(decision: .allow)
  }

  func denyCurrentPrompt() async {
    await submitCurrentPrompt(decision: .deny)
  }

  private func submitCurrentPrompt(decision: AccessDecision) async {
    guard let currentRequest else {
      return
    }

    let resolvedDecision = AccessPromptDecision(
      requestID: currentRequest.requestID,
      decision: decision,
      source: .user,
      rememberChoice: rememberChoice,
      respondedAt: now()
    )

    do {
      statusSnapshot = try await service.submitDecision(
        resolvedDecision, for: currentRequest, at: now())
      lastDecision = resolvedDecision
      lastError = nil
      rememberChoice = false
      self.currentRequest = try await service.claimNextPrompt(at: now())
      statusSnapshot = try await service.snapshot()
    } catch let error as IPCTransportError {
      lastError = error
    } catch {
      lastError = .storeFailure
    }
  }
}
