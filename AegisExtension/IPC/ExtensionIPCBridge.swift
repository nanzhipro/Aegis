import Foundation

public protocol ExtensionDecisionTransport: Sendable {
  func publishReady(detail: String) async throws -> IPCStatusSnapshot
  func enqueuePrompt(_ request: AccessPromptRequest) async throws -> IPCStatusSnapshot
  func awaitDecision(for request: AccessPromptRequest) async throws -> AccessPromptDecision
  func reloadPolicy() async throws -> IPCStatusSnapshot
  func snapshot() async throws -> IPCStatusSnapshot
}

public struct ExtensionIPCBridge: ExtensionDecisionTransport, Sendable {
  private let service: AegisIPCService

  public init(paths: SharedContainerPaths, policyStoreFileStore: LocalPolicyStoreFileStore? = nil) {
    self.service = AegisIPCService(paths: paths, policyStoreFileStore: policyStoreFileStore)
  }

  public func publishReady(detail: String = "extension-ready") async throws -> IPCStatusSnapshot {
    try await service.publish(endpoint: .extensionService, state: .ready, detail: detail)
  }

  public func enqueuePrompt(_ request: AccessPromptRequest) async throws -> IPCStatusSnapshot {
    try await service.enqueuePrompt(request)
  }

  public func awaitDecision(for request: AccessPromptRequest) async throws -> AccessPromptDecision {
    try await service.awaitDecision(for: request)
  }

  public func reloadPolicy() async throws -> IPCStatusSnapshot {
    try await service.reloadPolicy()
  }

  public func snapshot() async throws -> IPCStatusSnapshot {
    try await service.snapshot()
  }
}
