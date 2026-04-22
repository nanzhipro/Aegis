import Foundation

public struct TrustedProcessPolicy: Sendable {
  public struct Configuration: Sendable {
    public var trustedSigningIdentifiers: Set<String>
    public var trustedTeamIdentifiers: Set<String>
    public var trustedExecutablePathPrefixes: [String]

    public init(
      trustedSigningIdentifiers: Set<String> = [
        "com.nanzhipro.AegisApp",
        "com.nanzhipro.AegisAgent",
        "com.nanzhipro.AegisExtension",
      ],
      trustedTeamIdentifiers: Set<String> = [],
      trustedExecutablePathPrefixes: [String] = []
    ) {
      self.trustedSigningIdentifiers = trustedSigningIdentifiers
      self.trustedTeamIdentifiers = trustedTeamIdentifiers
      self.trustedExecutablePathPrefixes = trustedExecutablePathPrefixes
    }
  }

  private let configuration: Configuration

  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
  }

  public func matches(_ request: AccessPromptRequest) -> Bool {
    guard request.eventType == AccessEventType.authOpen else {
      return false
    }

    guard !request.isAppleSigned else {
      return false
    }

    if let signingIdentifier = request.signingIdentifier,
      configuration.trustedSigningIdentifiers.contains(signingIdentifier)
    {
      return true
    }

    if let teamIdentifier = request.teamIdentifier,
      configuration.trustedTeamIdentifiers.contains(teamIdentifier)
    {
      return true
    }

    return configuration.trustedExecutablePathPrefixes.contains {
      request.processPath.hasPrefix($0)
    }
  }
}
