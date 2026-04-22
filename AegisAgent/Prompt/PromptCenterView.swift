import SwiftUI

@MainActor
struct PromptCenterView: View {
  @Bindable var runtime: AgentRuntime

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("aegis.agent.subtitle")
            .font(.body)
            .foregroundStyle(.secondary)

          LabeledContent {
            Text(LocalizedStringKey(runtime.agentStatusKey))
          } label: {
            Text("aegis.agent.status")
          }

          LabeledContent {
            Text(verbatim: "\(runtime.pendingPromptCount)")
          } label: {
            Text("aegis.agent.pending")
          }

          Button("aegis.agent.refresh") {
            Task {
              await runtime.refresh()
            }
          }
        }

        Section("aegis.agent.prompt.title") {
          if let request = runtime.currentRequest {
            LabeledContent {
              Text(verbatim: request.workspaceName)
            } label: {
              Text("aegis.agent.prompt.workspace")
            }

            LabeledContent {
              Text(verbatim: request.targetPath)
                .font(.body.monospaced())
                .textSelection(.enabled)
            } label: {
              Text("aegis.agent.prompt.target")
            }

            LabeledContent {
              Text(verbatim: request.processPath)
                .font(.body.monospaced())
                .textSelection(.enabled)
            } label: {
              Text("aegis.agent.prompt.process")
            }

            Toggle("aegis.agent.remember_choice", isOn: $runtime.rememberChoice)

            HStack {
              Button("aegis.agent.deny") {
                Task {
                  await runtime.denyCurrentPrompt()
                }
              }

              Button("aegis.agent.allow") {
                Task {
                  await runtime.allowCurrentPrompt()
                }
              }
              .buttonStyle(.borderedProminent)
            }
          } else {
            Text("aegis.agent.waiting")
              .foregroundStyle(.secondary)
          }
        }

        if let lastDecision = runtime.lastDecision {
          Section("aegis.agent.last_decision") {
            Text(
              lastDecision.decision == .allow
                ? "aegis.agent.last_decision.allow" : "aegis.agent.last_decision.deny")
          }
        }

        if let lastError = runtime.lastError {
          Section("aegis.agent.error") {
            Text(verbatim: lastError.rawValue)
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("aegis.agent.title")
      .frame(minWidth: 460, minHeight: 380)
    }
    .task {
      await runtime.activate()
    }
  }
}

#Preview {
  PromptCenterView(runtime: AgentRuntime())
}
