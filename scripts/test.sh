#!/bin/sh
set -eu

ROOT_DIR=$(cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

PROJECT="Aegis.xcodeproj"
DESTINATION="platform=macOS"

xcodebuild -project "$PROJECT" -scheme AegisAgent -destination "$DESTINATION" build
xcodebuild -project "$PROJECT" -target AegisExtension build
xcodebuild -project "$PROJECT" -scheme AegisSharedTests -destination "$DESTINATION" test
xcodebuild -project "$PROJECT" -scheme AegisExtensionTests -destination "$DESTINATION" test
xcodebuild -project "$PROJECT" -scheme AegisAppTests -destination "$DESTINATION" test
xcodebuild -project "$PROJECT" -scheme AegisAppUITests -destination "$DESTINATION" test
xcodebuild -project "$PROJECT" -scheme ReleaseValidationTests -destination "$DESTINATION" test