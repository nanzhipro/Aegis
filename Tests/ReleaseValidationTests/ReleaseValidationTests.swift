import Foundation
import XCTest

final class ReleaseValidationTests: XCTestCase {
  func testReleaseScriptsExistAndParseAsShell() throws {
    let requiredScripts = [
      "bootstrap.sh",
      "archive.sh",
      "sign.sh",
      "notarize.sh",
      "package-dmg.sh",
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
          "./scripts/package-dmg.sh",
          "./scripts/notarize.sh",
          "./scripts/validate-release.sh",
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
    }

    let removedWorkflowURL = repositoryRoot.appending(
      path: ".github/workflows/privileged-smoke.yml")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: removedWorkflowURL.path()),
      "privileged smoke is now a local manual validation flow and should not be modelled as a GitHub workflow"
    )
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
