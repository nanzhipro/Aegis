import XCTest

final class AegisAppUITests: XCTestCase {
  @MainActor
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testEnglishFirstLaunchShowsOnboarding() {
    let app = launchApp(language: "en", forceOnboardingCompleted: false)

    XCTAssertTrue(
      app.staticTexts["Protect local folders with clear prompts"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSimplifiedChineseFirstLaunchShowsOnboarding() {
    let app = launchApp(language: "zh-Hans", forceOnboardingCompleted: false)

    XCTAssertTrue(app.staticTexts["用清晰提示保护本地文件夹"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testJapaneseFirstLaunchShowsOnboarding() {
    let app = launchApp(language: "ja", forceOnboardingCompleted: false)

    XCTAssertTrue(app.staticTexts["明確な確認でローカルフォルダを保護"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testDashboardAppearsWhenOnboardingIsForcedComplete() {
    let app = launchApp(language: "en", forceOnboardingCompleted: true)

    XCTAssertTrue(app.staticTexts["dashboard.title"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSettingsScreenCanOpenFromSidebar() {
    let app = launchApp(language: "en", forceOnboardingCompleted: true)

    app.staticTexts["Protected Folders"].click()

    XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testPseudolanguageLaunchesOnboardingContainer() {
    let app = launchApp(
      language: "en", forceOnboardingCompleted: false, forcePseudolocalization: true)
    let pseudolanguageBanner = app.descendants(matching: .any).matching(
      identifier: "pseudolanguage.banner"
    ).firstMatch

    XCTAssertTrue(pseudolanguageBanner.waitForExistence(timeout: 5))
  }

  @MainActor
  private func launchApp(
    language: String,
    forceOnboardingCompleted: Bool,
    forcePseudolocalization: Bool = false
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["AEGIS_USER_DEFAULTS_SUITE"] = "AegisAppUITests.\(UUID().uuidString)"
    app.launchEnvironment["AEGIS_FORCE_ONBOARDING_COMPLETED"] = forceOnboardingCompleted ? "1" : "0"
    app.launchEnvironment["AEGIS_FORCE_PSEUDO_LANGUAGE"] = forcePseudolocalization ? "1" : "0"
    app.launchEnvironment["AEGIS_UI_TEST_MODE"] = "1"
    app.launchEnvironment["AEGIS_SHARED_CONTAINER_ROOT"] =
      FileManager.default.temporaryDirectory
      .appendingPathComponent("AegisAppUITests-\(UUID().uuidString)", isDirectory: true)
      .path
    app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
    app.launch()
    return app
  }
}
