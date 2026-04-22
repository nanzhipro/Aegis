import SwiftUI

@MainActor
struct OnboardingFlowView: View {
  @Bindable var runtime: AppRuntime

  var body: some View {
    HStack(spacing: 0) {
      List(runtime.onboardingSteps, selection: $runtime.selectedOnboardingStep) { step in
        HStack(spacing: 10) {
          Image(systemName: step.symbolName)
            .foregroundStyle(
              step == runtime.selectedOnboardingStep ? Color.accentColor : Color.secondary)
          Text(LocalizedStringKey(step.titleKey))
        }
        .tag(step)
      }
      .frame(minWidth: 240, idealWidth: 260)
      .navigationTitle(Text("aegis.onboarding.sidebar.title"))

      Divider()

      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 12) {
            Image(systemName: runtime.selectedOnboardingStep.symbolName)
              .font(.system(size: 30, weight: .semibold))
              .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
              Text(LocalizedStringKey(runtime.selectedOnboardingStep.titleKey))
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("onboarding.title")
              HStack(spacing: 6) {
                Text("aegis.onboarding.progress")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                Text(
                  verbatim:
                    "\(runtime.currentOnboardingStepNumber) / \(runtime.onboardingSteps.count)"
                )
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
              }
            }
          }

          if runtime.isPseudolocalizationEnabled {
            Text(
              verbatim:
                "[!! Aegis pseudo-localization layout check with intentionally wide glyphs and extra padding !!]"
            )
            .font(.body)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
            )
            .accessibilityIdentifier("pseudolanguage.banner")
          }
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            switch runtime.selectedOnboardingStep {
            case .welcome:
              welcomeContent
            case .permissions:
              permissionsContent
            case .workspaces:
              workspacesContent
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        Divider()

        HStack {
          Button("aegis.onboarding.back", action: runtime.goBack)
            .accessibilityIdentifier("onboarding.back")
            .disabled(!runtime.canMoveBackwardInOnboarding)

          Spacer()

          Button("aegis.onboarding.finish_later", action: runtime.completeOnboarding)
            .accessibilityIdentifier("onboarding.finishLater")

          Button(action: runtime.advanceOnboarding) {
            Text(LocalizedStringKey(runtime.primaryOnboardingActionKey))
          }
          .accessibilityIdentifier("onboarding.primary")
          .buttonStyle(.borderedProminent)
        }
      }
      .padding(32)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .accessibilityIdentifier("onboarding.container")
  }

  private var welcomeContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("aegis.onboarding.welcome.body")
        .font(.title3)

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          onboardingBullet(symbolName: "internaldrive", key: "aegis.onboarding.welcome.local_only")
          onboardingBullet(symbolName: "wifi.slash", key: "aegis.onboarding.welcome.no_network")
          onboardingBullet(symbolName: "globe", key: "aegis.onboarding.welcome.languages")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var permissionsContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("aegis.onboarding.permissions.body")
        .font(.title3)

      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(runtime.readinessItems) { item in
            ReadinessIndicatorRow(item: item)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Text("aegis.onboarding.permissions.footer")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private var workspacesContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("aegis.onboarding.workspaces.body")
        .font(.title3)

      GroupBox {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(runtime.protectedWorkspaces) { workspace in
            VStack(alignment: .leading, spacing: 4) {
              Text(verbatim: workspace.name)
                .font(.headline)
              Text(verbatim: workspace.path)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            .accessibilityIdentifier("workspace.\(workspace.name)")
          }

          Divider()

          LabeledContent {
            Text(LocalizedStringKey(runtime.defaultTimeoutDecisionKey))
          } label: {
            Text("aegis.workspaces.timeout_title")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func onboardingBullet(symbolName: String, key: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbolName)
        .foregroundStyle(Color.accentColor)
        .frame(width: 18)
      Text(LocalizedStringKey(key))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
