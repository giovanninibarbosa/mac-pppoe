# Pull Request Description

## Summary

Modernizes this 2016-era macOS PPPoE client so it builds natively on Apple Silicon with the current Xcode 27 toolchain. The project was pinned to `SDKROOT = macosx10.11` with `ARCHS = ARCHS_STANDARD_32_64_BIT` (i386 included), PowerPC-era `GCC_MODEL_TUNING = G5`, `ZERO_LINK`, and `PREBINDING` — none of which exist on a modern Mac. The app now builds as a universal `arm64 + x86_64` binary with ARC enabled and all deprecated AppKit/SystemConfiguration API usage replaced.

### Build system (`build:` commits)

- `SDKROOT = macosx` (always-latest SDK), `MACOSX_DEPLOYMENT_TARGET = 12.0` (minimum supported by the Xcode 27 SDK)
- `ARCHS = $(ARCHS_STANDARD)` — universal arm64 + x86_64; removed `VALID_ARCHS = i386 x86_64`
- Removed dead flags: `GCC_MODEL_TUNING`, `ZERO_LINK`, `PREBINDING`, `COPY_PHASE_STRIP`, `GCC_ENABLE_FIX_AND_CONTINUE`, `GCC_DYNAMIC_NO_PIC`, `COMBINE_HIDPI_IMAGES`
- `CLANG_ENABLE_OBJC_ARC = YES` across all configurations
- Fixed malformed bundle identifier `com.com.cppfun` → `com.cppfun.pppoeclient`
- `ENABLE_HARDENED_RUNTIME = YES` (Release), `CODE_SIGN_STYLE = Automatic`, `USE_HEADERMAP = NO` (kills headermap warning)

### Info.plist

- Added `CFBundleShortVersionString` (1.1), `LSMinimumSystemVersion` (12.0), `NSHighResolutionCapable`, `LSApplicationCategoryType`

### Source (`refactor:` / `fix:` commits)

- Full ARC migration: manual `retain`/`release`/`autorelease`/`[super dealloc]` removed from `pppoeGUI` and `pppoeOperation`; singleton is now `dispatch_once`-based with nib-safe `init` guard
- Deprecated APIs replaced: `NSInformationalAlertStyle` → `NSAlertStyleInformational`, `NSOnState`/`NSOffState` → `NSControlStateValueOn`/`Off`, `initWithHTML:documentAttributes:` → `initWithHTML:options:documentAttributes:`
- Correctness fixes: missing `<string.h>` include (implicit-declaration is an error under modern clang), NULL-safety for the optional service name (`strlen(NULL)` crash), type-safety fixes (`nonnull` annotations, `size_t` lengths, CF type corrections)
- PPP dial/connect logic is otherwise byte-equivalent — no behavior changes

### Verification harness

- `scripts/verify.sh`: asserts arm64 slice via `lipo`, lists `otool -L` deps, checks codesign, 5-second launch smoke test

## Verification Results

| Check | Result |
|-------|--------|
| Host | macOS 27.2, Xcode 27.0 (27A266a), Apple Silicon |
| `xcodebuild -configuration Debug build` | SUCCEEDED, 0 warnings, 0 errors |
| `xcodebuild -configuration Release build` | SUCCEEDED, 0 warnings, 0 errors |
| `lipo -archs` | `x86_64 arm64` (universal) |
| `otool -L` | System frameworks only (Cocoa, Security, SystemConfiguration, Foundation, AppKit, CoreFoundation, libobjc, libSystem) |
| Codesign | Ad-hoc signed, hardened runtime (Release) |
| Launch smoke test (5s) | PASS — app runs, no crash |

Reproduce: `xcodebuild -project PPPoEClient.xcodeproj -target PPPoEClient -configuration Release build && scripts/verify.sh`

## Backward Compatibility

- **Intel Macs:** still supported via the universal binary; minimum OS raised from (implicit) 10.11 to **12.0 Monterey**, the oldest deployment target the current SDK accepts
- **i386:** dropped — Apple removed 32-bit support in macOS 10.15; no modern Mac can run it
- **PPPoE feature set:** unchanged; SystemConfiguration PPPoE APIs remain supported on macOS 27
- **Legacy Nib:** `MainMenu.nib` loads unmodified on modern AppKit; conversion to storyboard/xib intentionally left out of scope
- **Update checker:** the 2016-era update URL (`dev.cppfun.com`) is dead; the HTTP fetch fails silently at runtime as before (ATS exception retained)

## Dependency Migration

None needed — the app links only against system frameworks (Cocoa, Security, SystemConfiguration), all of which ship arm64-native slices on modern macOS. No CocoaPods/SPM/pkg-config introduction required.