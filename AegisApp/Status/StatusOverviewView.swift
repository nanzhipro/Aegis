import SwiftUI

@MainActor
struct StatusOverviewView: View {
  @Bindable var runtime: AppRuntime

  var body: some View {
    Group {
      switch runtime.screen {
      case .onboarding:
        OnboardingFlowView(runtime: runtime)
      case .dashboard:
        NavigationSplitView {
          List(AppRuntime.SidebarItem.allCases, selection: $runtime.selectedSidebarItem) { item in
            HStack(spacing: 10) {
              Image(systemName: item.symbolName)
                .foregroundStyle(.secondary)
              Text(LocalizedStringKey(item.titleKey))
            }
            .accessibilityIdentifier("sidebar.\(item.rawValue)")
            .tag(item)
          }
          .navigationTitle(Text("aegis.app.title"))
        } detail: {
          ScrollView {
            VStack(alignment: .leading, spacing: 24) {
              switch runtime.selectedSidebarItem {
              case .overview:
                overviewContent
              case .protectedFolders:
                AegisSettingsContent(runtime: runtime)
              }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
          }
          .accessibilityIdentifier("dashboard.container")
        }
      }
    }
    .task {
      await runtime.activate()
    }
  }

  private var overviewContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text("aegis.dashboard.title")
          .font(.largeTitle.weight(.semibold))
          .accessibilityIdentifier("dashboard.title")
        Text("aegis.dashboard.subtitle")
          .font(.title3)
          .foregroundStyle(.secondary)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          Text(LocalizedStringKey(runtime.readinessSummaryKey))
            .font(.headline)
          Text("aegis.readiness.summary.caption")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(runtime.readinessItems) { item in
            ReadinessIndicatorRow(item: item)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack {
        Button(LocalizedStringKey(runtime.loginItemActionKey)) {
          Task {
            if runtime.isAgentLoginItemEnabled {
              await runtime.unregisterAgentLoginItem()
            } else {
              await runtime.registerAgentLoginItem()
            }
          }
        }

        Button("aegis.dashboard.refresh_communication") {
          Task {
            await runtime.refreshCommunicationStatus()
          }
        }
      }

      Button("aegis.dashboard.reopen_onboarding", action: runtime.reopenOnboarding)
    }
  }

}

@MainActor
struct AegisSettingsScreen: View {
  @Bindable var runtime: AppRuntime

  var body: some View {
    ScrollView {
      AegisSettingsContent(runtime: runtime)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(minWidth: 860, minHeight: 560)
    .task {
      await runtime.activate()
    }
  }
}

@MainActor
struct AegisSettingsContent: View {
  @Bindable var runtime: AppRuntime

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text("aegis.settings.title")
          .font(.largeTitle.weight(.semibold))
          .accessibilityIdentifier("settings.title")
        Text("aegis.settings.subtitle")
          .font(.title3)
          .foregroundStyle(.secondary)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 16) {
          Text("aegis.settings.section.folders")
            .font(.headline)

          if runtime.protectedWorkspaces.isEmpty {
            Text("aegis.readiness.policy.detail.missing")
              .foregroundStyle(.secondary)
          } else {
            ForEach(runtime.protectedWorkspaces) { workspace in
              WorkspaceEditorRow(
                workspace: workspace,
                onSave: { name, path, isEnabled in
                  Task {
                    await runtime.saveProtectedWorkspace(
                      id: workspace.id,
                      name: name,
                      path: path,
                      isEnabled: isEnabled
                    )
                  }
                },
                onRemove: {
                  Task {
                    await runtime.removeProtectedWorkspace(id: workspace.id)
                  }
                }
              )
            }
          }

          Button("aegis.settings.add_folder") {
            Task {
              await runtime.addProtectedWorkspace()
            }
          }
          .accessibilityIdentifier("settings.addFolder")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 16) {
          Text("aegis.settings.section.default_behavior")
            .font(.headline)

          Picker("aegis.workspaces.timeout_title", selection: defaultTimeoutDecisionBinding) {
            Text("aegis.policy.decision.deny")
              .tag(AccessDecision.deny)
            Text("aegis.policy.decision.allow")
              .tag(AccessDecision.allow)
          }
          .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("aegis.settings.section.remembered_decisions")
              .font(.headline)
            Spacer()
            Button("aegis.settings.clear_remembered") {
              Task {
                await runtime.clearRememberedDecisions()
              }
            }
            .disabled(runtime.rememberedRules.isEmpty)
          }

          if runtime.rememberedRules.isEmpty {
            Text("aegis.settings.no_remembered_decisions")
              .foregroundStyle(.secondary)
          } else {
            ForEach(runtime.rememberedRules) { rule in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(verbatim: runtime.workspaceDisplayName(for: rule.workspaceID))
                    .font(.headline)
                  Spacer()
                  DecisionBadge(decision: rule.decision)
                }

                Text(verbatim: rule.process.executablePath)
                  .font(.body.monospaced())
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)

                Text(verbatim: runtime.formattedDiagnosticDate(rule.updatedAt))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("aegis.settings.section.diagnostics")
              .font(.headline)
            Spacer()
            Button("aegis.dashboard.refresh_communication") {
              Task {
                await runtime.refreshCommunicationStatus()
              }
            }
          }

          ForEach(runtime.diagnosticItems) { item in
            DiagnosticRow(item: item)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var defaultTimeoutDecisionBinding: Binding<AccessDecision> {
    Binding(
      get: { runtime.defaultTimeoutDecision },
      set: { newValue in
        Task {
          await runtime.setDefaultTimeoutDecision(newValue)
        }
      }
    )
  }
}

struct ReadinessIndicatorRow: View {
  let item: AppRuntime.ReadinessItem

  var body: some View {
    let tint = color(for: item.indicator.state)

    return HStack(alignment: .top, spacing: 12) {
      Image(systemName: item.kind.symbolName)
        .foregroundStyle(tint)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 4) {
        Text(LocalizedStringKey(item.kind.titleKey))
          .font(.headline)

        if let detailKey = item.indicator.detail {
          Text(LocalizedStringKey(detailKey))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      StatusStateBadge(state: item.indicator.state)
    }
    .accessibilityIdentifier("readiness.\(item.kind.rawValue)")
  }

  private func color(for state: ComponentStatus.State) -> Color {
    switch state {
    case .ready:
      return .green
    case .needsAttention:
      return .orange
    case .unavailable:
      return .red
    case .unknown:
      return .secondary
    }
  }
}

private struct WorkspaceEditorRow: View {
  let workspace: ProtectedWorkspace
  let onSave: (String, String, Bool) -> Void
  let onRemove: () -> Void

  @State private var name: String
  @State private var path: String
  @State private var isEnabled: Bool

  init(
    workspace: ProtectedWorkspace,
    onSave: @escaping (String, String, Bool) -> Void,
    onRemove: @escaping () -> Void
  ) {
    self.workspace = workspace
    self.onSave = onSave
    self.onRemove = onRemove
    _name = State(initialValue: workspace.name)
    _path = State(initialValue: workspace.path)
    _isEnabled = State(initialValue: workspace.isEnabled)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField("aegis.settings.workspace_name", text: $name)
        .textFieldStyle(.roundedBorder)

      TextField("aegis.settings.workspace_path", text: $path)
        .textFieldStyle(.roundedBorder)

      Toggle("aegis.settings.workspace_enabled", isOn: $isEnabled)

      HStack {
        Button("aegis.settings.save_folder") {
          onSave(name, path, isEnabled)
        }
        .disabled(!isSaveEnabled)

        Button("aegis.settings.remove_folder", role: .destructive) {
          onRemove()
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var isSaveEnabled: Bool {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasChanges =
      trimmedName != workspace.name || trimmedPath != workspace.path
      || isEnabled != workspace.isEnabled
    return !trimmedName.isEmpty && !trimmedPath.isEmpty && hasChanges
  }
}

private struct DecisionBadge: View {
  let decision: AccessDecision

  var body: some View {
    Text(LocalizedStringKey(labelKey))
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(color.opacity(0.16)))
      .foregroundStyle(color)
  }

  private var labelKey: String {
    switch decision {
    case .allow:
      return "aegis.policy.decision.allow"
    case .deny:
      return "aegis.policy.decision.deny"
    }
  }

  private var color: Color {
    switch decision {
    case .allow:
      return .green
    case .deny:
      return .orange
    }
  }
}

private struct DiagnosticRow: View {
  let item: AppRuntime.DiagnosticItem

  var body: some View {
    LabeledContent {
      if item.id == "policy-store-path" {
        Text(verbatim: item.value)
          .font(.body.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      } else {
        Text(verbatim: item.value)
          .font(.body)
      }
    } label: {
      Text(LocalizedStringKey(item.titleKey))
    }
  }
}

private struct StatusStateBadge: View {
  let state: ComponentStatus.State

  var body: some View {
    Text(LocalizedStringKey(labelKey))
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(color.opacity(0.16)))
      .foregroundStyle(color)
  }

  private var labelKey: String {
    switch state {
    case .ready:
      return "aegis.state.ready"
    case .needsAttention:
      return "aegis.state.needs_attention"
    case .unavailable:
      return "aegis.state.unavailable"
    case .unknown:
      return "aegis.state.unknown"
    }
  }

  private var color: Color {
    switch state {
    case .ready:
      return .green
    case .needsAttention:
      return .orange
    case .unavailable:
      return .red
    case .unknown:
      return .secondary
    }
  }
}

#Preview {
  let suiteName = "Aegis.StatusOverview.Preview"
  let defaults = UserDefaults(suiteName: suiteName) ?? .standard
  defaults.removePersistentDomain(forName: suiteName)

  return StatusOverviewView(
    runtime: AppRuntime(
      configuration: .init(
        userDefaults: defaults,
        homeDirectoryURL: URL(fileURLWithPath: "/Users/preview", isDirectory: true),
        forcedOnboardingCompleted: true,
        forcedPseudolocalization: false,
        sharedContainerPaths: .temporary(named: "StatusOverviewPreview")
      )
    )
  )
}
