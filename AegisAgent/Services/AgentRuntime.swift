import Foundation
import Observation

@MainActor
@Observable
final class AgentRuntime {
  struct Configuration {
    var sharedContainerPaths: SharedContainerPaths
    var ipcController: (any AgentIPCControlling)?
    var now: @Sendable () -> Date

    init(
      sharedContainerPaths: SharedContainerPaths = .defaultRoot(),
      ipcController: (any AgentIPCControlling)? = nil,
      now: @escaping @Sendable () -> Date = { Date() }
    ) {
      self.sharedContainerPaths = sharedContainerPaths
      self.ipcController = ipcController
      self.now = now
    }

    static func live() -> Configuration {
      Configuration()
    }
  }

  private let ipcController: any AgentIPCControlling
  private let now: @Sendable () -> Date

  private(set) var statusSnapshot: IPCStatusSnapshot
  private(set) var currentRequest: AccessPromptRequest?
  private(set) var lastDecision: AccessPromptDecision?
  private(set) var lastError: IPCTransportError?
  var rememberChoice = false

  init(
    configuration: Configuration = .live(),
    service: AegisIPCService? = nil,
    ipcController: (any AgentIPCControlling)? = nil
  ) {
    let resolvedIPCController =
      ipcController
      ?? configuration.ipcController
      ?? service.map { FileBackedAgentIPCController(service: $0) }
      ?? AegisAgentXPCController()
    self.ipcController = resolvedIPCController
    self.now = configuration.now
    self.statusSnapshot = .empty(now: configuration.now())

    self.ipcController.onPromptPresented = { [weak self] request in
      Task { @MainActor [weak self] in
        self?.handlePresentedPrompt(request)
      }
    }
    self.ipcController.onPromptCancelled = { [weak self] requestID in
      Task { @MainActor [weak self] in
        self?.handleCancelledPrompt(requestID)
      }
    }
    self.ipcController.onPolicyDidReload = { [weak self] snapshot in
      Task { @MainActor [weak self] in
        self?.statusSnapshot = snapshot
        self?.lastError = nil
      }
    }
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
    max(statusSnapshot.pendingPromptCount, currentRequest == nil ? 0 : 1)
  }

  func activate() async {
    do {
      statusSnapshot = try await ipcController.activate()
      lastError = nil
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
      self.currentRequest = nil
      statusSnapshot = try await ipcController.submitDecision(resolvedDecision, for: currentRequest)
      lastDecision = resolvedDecision
      lastError = nil
      rememberChoice = false
    } catch let error as IPCTransportError {
      lastError = error
    } catch {
      lastError = .storeFailure
    }
  }

  private func handlePresentedPrompt(_ request: AccessPromptRequest) {
    currentRequest = request
    statusSnapshot.pendingPromptCount = max(statusSnapshot.pendingPromptCount, 1)
    statusSnapshot.update(endpoint: .agent, state: .busy, detail: "prompt-presenting", at: now())
    lastError = nil
  }

  private func handleCancelledPrompt(_ requestID: UUID) {
    guard currentRequest?.requestID == requestID else {
      return
    }

    currentRequest = nil
    statusSnapshot.pendingPromptCount = max(statusSnapshot.pendingPromptCount - 1, 0)
    statusSnapshot.update(endpoint: .agent, state: .ready, detail: "agent-ready", at: now())
  }
}
