import SwiftUI

@main
@MainActor
struct AegisAgentApp: App {
  @State private var runtime = AgentRuntime()

  var body: some Scene {
    WindowGroup {
      PromptCenterView(runtime: runtime)
    }
  }
}
