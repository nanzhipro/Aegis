import SwiftUI

@main
@MainActor
struct AegisApp: App {
  @State private var runtime = AppRuntime()

  var body: some Scene {
    WindowGroup {
      StatusOverviewView(runtime: runtime)
    }
  }
}
