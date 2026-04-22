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
      (
        "privileged-smoke.yml",
        [
          "self-hosted",
          "macOS",
          "aegis-privileged",
          "./scripts/bootstrap.sh",
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
  }

  func testBuildProductsContainReleaseRelevantArtifacts() {
    let productsDirectoryURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
    let requiredProducts = [
      "AegisApp.app",
      "AegisAgent.app",
      "AegisExtension.systemextension",
    ]

    for productName in requiredProducts {
      let productURL = productsDirectoryURL.appending(path: productName)
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: productURL.path()),
        "Expected build product \(productName) at \(productURL.path())")
    }
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
}
