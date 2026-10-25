#!/bin/bash
# Builds "build/Measuring Tool.app". Needs only the Xcode Command Line Tools
# (`xcode-select --install`); pass --universal for an Apple silicon + Intel build (needs Xcode).
set -euo pipefail
cd "$(dirname "$0")"

flags=(-c release)
if [[ "${1:-}" == "--universal" ]]; then
  flags+=(--arch arm64 --arch x86_64)
fi

swift build "${flags[@]}"
bin_dir="$(swift build "${flags[@]}" --show-bin-path)"

app="build/Measuring Tool.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/MeasuringTool" "$app/Contents/MacOS/"
cp Support/Info.plist "$app/Contents/"
# Ad-hoc signature: enough to run on your own Mac, including Apple silicon.
codesign --force --sign - "$app"

echo "Built $app ($(du -sh "$app" | cut -f1))"
