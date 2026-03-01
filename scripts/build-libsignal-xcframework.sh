#!/bin/bash
#
# build-libsignal-xcframework.sh
#
# Downloads the prebuilt libsignal_ffi binary from Signal's build artifacts,
# packages it as an xcframework for SPM consumption, and computes the checksum.
#
# Usage:
#   ./scripts/build-libsignal-xcframework.sh 0.87.5
#
# Output:
#   output/SignalFfi.xcframework.zip   — upload this to GitHub Release
#   Prints the checksum to use in Package.swift
#
# Requirements:
#   - Xcode (xcodebuild, lipo)
#   - swift (for checksum computation)
#   - curl
#   - A local clone of the libsignal fork (for headers)

set -euo pipefail

VERSION="${1:?Usage: $0 <version> [fork-repo-path]}"
FORK_REPO="${2:-$(cd "$(dirname "$0")/.." && pwd)/../libsignal}"

WORK_DIR=$(mktemp -d)
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/output"
HEADERS_DIR="${FORK_REPO}/swift/Sources/SignalFfi"

echo "=== libsignal xcframework builder ==="
echo "Version:   ${VERSION}"
echo "Fork repo: ${FORK_REPO}"
echo "Work dir:  ${WORK_DIR}"
echo ""

# --------------------------------------------------
# Validate
# --------------------------------------------------
if [ ! -d "${HEADERS_DIR}" ]; then
  echo "ERROR: Headers not found at ${HEADERS_DIR}"
  echo "Pass the path to your libsignal fork clone as the second argument."
  echo "  $0 ${VERSION} /path/to/libsignal"
  exit 1
fi

# --------------------------------------------------
# M2. Download prebuilt binary
# --------------------------------------------------
echo "[1/6] Downloading prebuilt binary..."
DOWNLOAD_URL="https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v${VERSION}.tar.gz"
curl -L --fail -o "${WORK_DIR}/libsignal-ios.tar.gz" "${DOWNLOAD_URL}"
echo "  Downloaded $(du -h "${WORK_DIR}/libsignal-ios.tar.gz" | cut -f1)"

# --------------------------------------------------
# Extract
# --------------------------------------------------
echo "[2/6] Extracting..."
tar xzf "${WORK_DIR}/libsignal-ios.tar.gz" -C "${WORK_DIR}"

DEVICE_LIB="${WORK_DIR}/target/aarch64-apple-ios/release/libsignal_ffi.a"
SIM_ARM64_LIB="${WORK_DIR}/target/aarch64-apple-ios-sim/release/libsignal_ffi.a"
SIM_X86_LIB="${WORK_DIR}/target/x86_64-apple-ios/release/libsignal_ffi.a"

for lib in "${DEVICE_LIB}" "${SIM_ARM64_LIB}" "${SIM_X86_LIB}"; do
  if [ ! -f "${lib}" ]; then
    echo "ERROR: Expected library not found: ${lib}"
    exit 1
  fi
done
echo "  Found all 3 architecture slices"

# --------------------------------------------------
# M3. Create fat simulator library
# --------------------------------------------------
echo "[3/6] Creating fat simulator library..."
FAT_SIM_LIB="${WORK_DIR}/libsignal_ffi_sim.a"
lipo -create "${SIM_ARM64_LIB}" "${SIM_X86_LIB}" -output "${FAT_SIM_LIB}"
echo "  $(lipo -info "${FAT_SIM_LIB}")"

# --------------------------------------------------
# M4. Create xcframework
# --------------------------------------------------
echo "[4/6] Creating xcframework..."
XCFRAMEWORK="${WORK_DIR}/SignalFfi.xcframework"

# Try xcodebuild first, fall back to manual creation if bitcode error occurs
if xcodebuild -create-xcframework \
  -library "${DEVICE_LIB}" -headers "${HEADERS_DIR}" \
  -library "${FAT_SIM_LIB}" -headers "${HEADERS_DIR}" \
  -output "${XCFRAMEWORK}" 2>/dev/null; then
  echo "  Created via xcodebuild"
else
  echo "  xcodebuild failed (likely bitcode issue), creating manually..."

  # Device slice
  mkdir -p "${XCFRAMEWORK}/ios-arm64/Headers"
  cp "${DEVICE_LIB}" "${XCFRAMEWORK}/ios-arm64/libsignal_ffi.a"
  cp "${HEADERS_DIR}/module.modulemap" "${XCFRAMEWORK}/ios-arm64/Headers/"
  cp "${HEADERS_DIR}/signal_ffi.h" "${XCFRAMEWORK}/ios-arm64/Headers/"
  cp "${HEADERS_DIR}/signal_ffi_testing.h" "${XCFRAMEWORK}/ios-arm64/Headers/"

  # Simulator slice
  mkdir -p "${XCFRAMEWORK}/ios-arm64_x86_64-simulator/Headers"
  cp "${FAT_SIM_LIB}" "${XCFRAMEWORK}/ios-arm64_x86_64-simulator/libsignal_ffi.a"
  cp "${HEADERS_DIR}/module.modulemap" "${XCFRAMEWORK}/ios-arm64_x86_64-simulator/Headers/"
  cp "${HEADERS_DIR}/signal_ffi.h" "${XCFRAMEWORK}/ios-arm64_x86_64-simulator/Headers/"
  cp "${HEADERS_DIR}/signal_ffi_testing.h" "${XCFRAMEWORK}/ios-arm64_x86_64-simulator/Headers/"

  # Info.plist
  cat > "${XCFRAMEWORK}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>libsignal_ffi.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
		<dict>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>ios-arm64_x86_64-simulator</string>
			<key>LibraryPath</key>
			<string>libsignal_ffi.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVariant</key>
			<string>simulator</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
PLIST
  echo "  Created manually"
fi

# --------------------------------------------------
# M5. Zip + checksum
# --------------------------------------------------
echo "[5/6] Zipping..."
mkdir -p "${OUTPUT_DIR}"
ZIP_PATH="${OUTPUT_DIR}/SignalFfi.xcframework.zip"
(cd "${WORK_DIR}" && zip -r "${ZIP_PATH}" SignalFfi.xcframework) > /dev/null
echo "  Output: ${ZIP_PATH} ($(du -h "${ZIP_PATH}" | cut -f1))"

echo "[6/6] Computing checksum..."
CHECKSUM=$(swift package compute-checksum "${ZIP_PATH}")
echo ""

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo "==========================================="
echo " DONE"
echo "==========================================="
echo ""
echo "1. Upload to GitHub Release:"
echo "   ${ZIP_PATH}"
echo ""
echo "2. Tag: v${VERSION}"
echo ""
echo "3. Package.swift binaryTarget checksum:"
echo "   ${CHECKSUM}"
echo ""
echo "4. Package.swift snippet:"
echo ""
cat <<EOF
    .binaryTarget(
      name: "SignalFfi",
      url: "https://github.com/martinolee/libsignal/releases/download/v${VERSION}/SignalFfi.xcframework.zip",
      checksum: "${CHECKSUM}"
    ),
EOF
echo ""

# Cleanup
rm -rf "${WORK_DIR}"
