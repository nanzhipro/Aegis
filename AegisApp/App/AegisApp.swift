import AppKit
import SwiftUI

@main
@MainActor
struct AegisApp: App {
  static let mainWindowID = "main-window"

  @State private var runtime = AppRuntime()

  var body: some Scene {
    WindowGroup(id: Self.mainWindowID) {
      StatusOverviewView(runtime: runtime)
    }
    .defaultSize(width: 860, height: 560)

    Settings {
      AegisSettingsScreen(runtime: runtime)
    }

    MenuBarExtra {
      AegisStatusMenuContent(runtime: runtime)
    } label: {
      Image(systemName: "shield.lefthalf.filled")
        .symbolRenderingMode(.hierarchical)
        .accessibilityLabel(Text("aegis.app.title"))
    }
    .menuBarExtraStyle(.menu)
  }
}

@MainActor
private struct AegisStatusMenuContent: View {
  @Bindable var runtime: AppRuntime
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("aegis.app.title")
        .font(.headline)

      Text(LocalizedStringKey(runtime.readinessSummaryKey))
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Divider()

      Button {
        openWindow(id: AegisApp.mainWindowID)
        NSApplication.shared.activate(ignoringOtherApps: true)
      } label: {
        Label(LocalizedStringKey(runtime.openOnboardingActionKey), systemImage: "rectangle.stack")
      }

      Button {
        runtime.installSystemExtension()
        openWindow(id: AegisApp.mainWindowID)
        NSApplication.shared.activate(ignoringOtherApps: true)
      } label: {
        Label(
          LocalizedStringKey(runtime.systemExtensionInstallActionKey),
          systemImage: "puzzlepiece.extension"
        )
      }
      .disabled(runtime.systemExtensionInstallationState.isInProgress)

      SettingsLink {
        Label("aegis.menu.open_settings", systemImage: "gearshape")
      }

      Divider()

      Button("aegis.menu.quit", role: .destructive) {
        NSApplication.shared.terminate(nil)
      }
    }
    .task {
      await runtime.activate()
    }
  }
}
