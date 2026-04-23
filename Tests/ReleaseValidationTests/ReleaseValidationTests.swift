import Foundation
import XCTest

final class ReleaseValidationTests: XCTestCase {
  func testReleaseScriptsExistAndParseAsShell() throws {
    let requiredScripts = [
      "bootstrap.sh",
      "archive.sh",
      "sign.sh",
      "notarize.sh",
      "package-app.sh",
      "validate-release.sh",
      "release-common.sh",
      "test.sh",
    ]

    for scriptName in requiredScripts {
      let scriptURL = repositoryRoot.appending(path: "scripts/\(scriptName)")
      XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path()))
      XCTAssertTrue(FileManager.default.isExecutableFile(atPath: scriptURL.path()))
      try assertShellSyntax(for: scriptURL)
    }

    let legacyDMGScriptURL = repositoryRoot.appending(path: "scripts/package-dmg.sh")
    if FileManager.default.fileExists(atPath: legacyDMGScriptURL.path()) {
      let contents = try String(contentsOf: legacyDMGScriptURL, encoding: .utf8)
      XCTAssertTrue(contents.contains("disabled"))
      XCTAssertFalse(contents.contains("hdiutil create"))
      try assertShellSyntax(for: legacyDMGScriptURL)
    }
  }

  func testReleaseWorkflowsPinRunnersAndDelegateToScripts() throws {
    let expectations: [(String, [String])] = [
      (
        "ci.yml",
        [
          "runs-on: macos-14",
          "./scripts/bootstrap.sh",
          "./scripts/test.sh",
        ]
      ),
      (
        "release.yml",
        [
          "runs-on: macos-14",
          "./scripts/bootstrap.sh",
          "./scripts/test.sh",
          "./scripts/archive.sh",
          "./scripts/sign.sh",
          "./scripts/package-app.sh",
          "./scripts/notarize.sh",
          "./scripts/validate-release.sh",
          "build/release/AegisApp.zip",
        ]
      ),
    ]

    for (fileName, requiredSnippets) in expectations {
      let workflowURL = repositoryRoot.appending(path: ".github/workflows/\(fileName)")
      XCTAssertTrue(FileManager.default.fileExists(atPath: workflowURL.path()))

      let contents = try String(contentsOf: workflowURL, encoding: .utf8)
      for snippet in requiredSnippets {
        XCTAssertTrue(contents.contains(snippet), "Expected \(fileName) to contain \(snippet)")
      }

      XCTAssertFalse(contents.contains("package-dmg.sh"))
      XCTAssertFalse(contents.contains("AegisApp.dmg"))
    }

    let removedWorkflowURL = repositoryRoot.appending(
      path: ".github/workflows/privileged-smoke.yml")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: removedWorkflowURL.path()),
      "privileged smoke is now a local manual validation flow and should not be modelled as a GitHub workflow"
    )
  }

  func testReleaseScriptsTargetAppAndZipArtifactsOnly() throws {
    let signScript = try String(
      contentsOf: repositoryRoot.appending(path: "scripts/sign.sh"),
      encoding: .utf8
    )
    XCTAssertTrue(signScript.contains("$ZIP_PATH"))

    let packageScript = try String(
      contentsOf: repositoryRoot.appending(path: "scripts/package-app.sh"),
      encoding: .utf8
    )
    XCTAssertTrue(packageScript.contains("ditto -c -k --keepParent"))
    XCTAssertTrue(packageScript.contains("$ZIP_PATH"))

    let notarizeScript = try String(
      contentsOf: repositoryRoot.appending(path: "scripts/notarize.sh"),
      encoding: .utf8
    )
    XCTAssertTrue(notarizeScript.contains("notarytool submit \"$ZIP_PATH\""))
    XCTAssertTrue(notarizeScript.contains("stapler staple \"$EXPORTED_APP_PATH\""))
    XCTAssertFalse(notarizeScript.contains("DMG_PATH"))

    let validateScript = try String(
      contentsOf: repositoryRoot.appending(path: "scripts/validate-release.sh"),
      encoding: .utf8
    )
    XCTAssertTrue(validateScript.contains("codesign --verify --deep --strict --verbose=3"))
    XCTAssertTrue(
      validateScript.contains("codesign -dvvv --entitlements :- \"$EXPORTED_APP_PATH\""))
    XCTAssertTrue(validateScript.contains("codesign -dvvv --entitlements :- \"$agent_app_path\""))
    XCTAssertTrue(validateScript.contains("codesign -dvvv --entitlements :- \"$extension_path\""))
    XCTAssertTrue(validateScript.contains("spctl --assess --type execute"))
    XCTAssertTrue(validateScript.contains("xcrun stapler validate \"$EXPORTED_APP_PATH\""))
    XCTAssertFalse(validateScript.contains("spctl --assess --type install"))
    XCTAssertFalse(validateScript.contains("pkgutil --check-signature"))
    XCTAssertFalse(validateScript.contains("DMG_PATH"))
  }

  func testProjectDeclaresReleaseRelevantArtifacts() throws {
    let requiredProducts = [
      (target: "AegisApp", product: "AegisApp.app"),
      (target: "AegisAgent", product: "AegisAgent.app"),
      (target: "AegisExtension", product: "AegisExtension.systemextension"),
    ]

    for entry in requiredProducts {
      let settings = try buildSettings(forTarget: entry.target)
      XCTAssertEqual(
        settings["FULL_PRODUCT_NAME"],
        entry.product,
        "Expected target \(entry.target) to declare product \(entry.product)"
      )
      XCTAssertTrue(
        settings["TARGET_BUILD_DIR", default: ""].contains("/Build/Products/Debug"),
        "Expected target \(entry.target) to emit Debug build products into DerivedData"
      )
    }
  }

  func testAegisAppUsesMenuBarOnlyModeAndEmbedsSystemExtension() throws {
    let settings = try buildSettings(forTarget: "AegisApp")

    XCTAssertEqual(settings["INFOPLIST_KEY_LSUIElement"], "YES")

    let projectFileURL = repositoryRoot.appending(path: "Aegis.xcodeproj/project.pbxproj")
    let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

    XCTAssertTrue(projectContents.contains("Embed System Extension"))
    XCTAssertTrue(projectContents.contains("Contents/Library/SystemExtensions"))
  }

  func testAegisExtensionDeclaresSystemExtensionUsageDescription() throws {
    let settings = try buildSettings(forTarget: "AegisExtension")

    XCTAssertFalse(
      settings["INFOPLIST_KEY_NSSystemExtensionUsageDescription", default: ""].isEmpty,
      "Expected AegisExtension to declare NSSystemExtensionUsageDescription in its generated Info.plist"
    )
  }

  func testAegisAppEmbedsAgentBundleAndLaunchAgentPlist() throws {
    let projectFileURL = repositoryRoot.appending(path: "Aegis.xcodeproj/project.pbxproj")
    let projectContents = try String(contentsOf: projectFileURL, encoding: .utf8)

    XCTAssertTrue(projectContents.contains("Embed Agent Bundle"))
    XCTAssertTrue(projectContents.contains("Contents/Library/LoginItems/AegisAgent.app"))
    XCTAssertTrue(
      projectContents.contains(
        "Contents/Library/LaunchAgents/com.nanzhipro.AegisAgent.plist"))

    let launchAgentPlistURL = repositoryRoot.appending(
      path: "AegisAgent/Resources/com.nanzhipro.AegisAgent.plist")
    XCTAssertTrue(FileManager.default.fileExists(atPath: launchAgentPlistURL.path()))

    let plistData = try Data(contentsOf: launchAgentPlistURL)
    let plist = try XCTUnwrap(
      try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any])

    XCTAssertEqual(plist["Label"] as? String, "com.nanzhipro.AegisAgent")
    XCTAssertEqual(
      plist["BundleProgram"] as? String,
      "Contents/Library/LoginItems/AegisAgent.app/Contents/MacOS/AegisAgent")
  }

  private var repositoryRoot: URL {
    URL(filePath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func assertShellSyntax(for scriptURL: URL) throws {
    let process = Process()
    let errorPipe = Pipe()

    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = ["-n", scriptURL.path()]
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let diagnostics = String(
      decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    XCTAssertEqual(process.terminationStatus, 0, diagnostics)
  }

  private func buildSettings(forTarget target: String) throws -> [String: String] {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.currentDirectoryURL = repositoryRoot
    process.executableURL = URL(filePath: "/usr/bin/xcrun")
    process.arguments = [
      "xcodebuild",
      "-project",
      "Aegis.xcodeproj",
      "-target",
      target,
      "-configuration",
      "Debug",
      "-showBuildSettings",
    ]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(
      decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let diagnostics = String(
      decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    XCTAssertEqual(process.terminationStatus, 0, diagnostics)

    var settings: [String: String] = [:]
    for line in output.split(separator: "\n") {
      guard let separatorRange = line.range(of: " = ") else {
        continue
      }

      let key = line[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespaces)
      let value = line[separatorRange.upperBound...].trimmingCharacters(in: .whitespaces)
      settings[key] = value
    }

    return settings
  }
}
