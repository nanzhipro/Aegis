import Foundation
import Observation
import SystemExtensions

/// Installation state for the bundled System Extension. The host App uses this to surface
/// activation progress in the menu bar and diagnostics view.
public enum SystemExtensionInstallationState: Equatable, Sendable {
  case idle
  case requesting
  case awaitingUserApproval
  case willCompleteAfterReboot
  case activated
  case failed(reason: String)

  public var isInProgress: Bool {
    switch self {
    case .requesting, .awaitingUserApproval:
      return true
    default:
      return false
    }
  }

  public var isActivated: Bool {
    if case .activated = self { return true }
    return false
  }
}

/// Wraps `OSSystemExtensionManager` so the main App can request activation of the embedded
/// AegisExtension.systemextension bundle. The installer keeps a strong reference to the
/// delegate throughout the request lifetime because OSSystemExtensionManager holds it weakly.
@MainActor
public final class SystemExtensionInstaller {
  public static let defaultExtensionIdentifier = "com.nanzhipro.AegisExtension"

  private let extensionIdentifier: String
  private let manager: OSSystemExtensionManager
  private var pendingDelegate: SystemExtensionRequestDelegate?

  public private(set) var state: SystemExtensionInstallationState = .idle

  public init(
    extensionIdentifier: String = SystemExtensionInstaller.defaultExtensionIdentifier,
    manager: OSSystemExtensionManager = .shared
  ) {
    self.extensionIdentifier = extensionIdentifier
    self.manager = manager
  }

  /// Submits an activation request. The returned state is updated as the request progresses via
  /// `onStateChange`. The closure is invoked on the main actor.
  public func activate(onStateChange: @escaping @MainActor (SystemExtensionInstallationState) -> Void) {
    pendingDelegate = nil
    state = .requesting
    onStateChange(state)

    let delegate = SystemExtensionRequestDelegate { [weak self] newState in
      guard let self else { return }
      self.state = newState
      onStateChange(newState)
      if !newState.isInProgress {
        self.pendingDelegate = nil
      }
    }
    pendingDelegate = delegate

    let request = OSSystemExtensionRequest.activationRequest(
      forExtensionWithIdentifier: extensionIdentifier,
      queue: .main
    )
    request.delegate = delegate
    manager.submitRequest(request)
  }
}

/// Bridges OSSystemExtension delegate callbacks into a `@MainActor` closure.
private final class SystemExtensionRequestDelegate: NSObject, OSSystemExtensionRequestDelegate,
  @unchecked Sendable
{
  private let onStateChange: @MainActor (SystemExtensionInstallationState) -> Void

  init(onStateChange: @escaping @MainActor (SystemExtensionInstallationState) -> Void) {
    self.onStateChange = onStateChange
  }

  func request(
    _ request: OSSystemExtensionRequest,
    actionForReplacingExtension existing: OSSystemExtensionProperties,
    withExtension ext: OSSystemExtensionProperties
  ) -> OSSystemExtensionRequest.ReplacementAction {
    .replace
  }

  func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
    let onStateChange = self.onStateChange
    Task { @MainActor in
      onStateChange(.awaitingUserApproval)
    }
  }

  func request(
    _ request: OSSystemExtensionRequest,
    didFinishWithResult result: OSSystemExtensionRequest.Result
  ) {
    let onStateChange = self.onStateChange
    Task { @MainActor in
      switch result {
      case .completed:
        onStateChange(.activated)
      case .willCompleteAfterReboot:
        onStateChange(.willCompleteAfterReboot)
      @unknown default:
        onStateChange(.failed(reason: "aegis.system_extension.error.unknown_result"))
      }
    }
  }

  func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
    let description = (error as NSError).localizedDescription
    let onStateChange = self.onStateChange
    Task { @MainActor in
      onStateChange(.failed(reason: description))
    }
  }
}
