# PPPoE Client macOS Modernization Migration Spec

## Goal

Modernize the 11-year-old PPPoEClient macOS app (last touched 2016, targeting macOS 10.11 / i386 / x86_64) so it builds natively on Apple Silicon (`arm64`) with the current Xcode 27 / macOS 27 toolchain, adopts ARC, clears deprecated APIs, and ships a clean, testable build.

## Current State (Architecture Audit)

### Legacy build system findings

| Area | Legacy value | Problem on Apple Silicon |
|------|--------------|--------------------------|
| Project format | `objectVersion = 46`, `compatibilityVersion = "Xcode 3.2"` | Opens, but stuck in 2009-era schema; no object-level modernization |
| SDK | `SDKROOT = macosx10.11` | SDK no longer installed; modern Xcode cannot resolve |
| Architectures | `ARCHS = $(ARCHS_STANDARD_32_64_BIT)` | Includes i386. i386 removed from macOS 10.15+/Catalina; dead on arm64 hosts |
| Arch filter | `VALID_ARCHS = "i386 x86_64"` (Release) | Excludes arm64 entirely |
| CPU tuning | `GCC_MODEL_TUNING = G5` | PowerPC G5 flag; meaningless to modern clang |
| Linking | `PREBINDING = NO`, `ZERO_LINK = YES` (Debug), `COPY_PHASE_STRIP` | Prebinding removed from macOS; ZeroLink dead since Xcode 4; flags ignored but noisy |
| Deployment target | None set | Defaults to SDK root assumptions; no `LSMinimumSystemVersion` |
| Bundle ID | `PRODUCT_BUNDLE_IDENTIFIER = com.com.cppfun` | Malformed (double TLD, no product name) |
| Signing | None | Required for hardened runtime / notarization; `CODE_SIGN_IDENTITY` absent |
| pch | `PPPoEClient_Prefix.pch` with `#ifdef __OBJC__` | Pre-ARC boilerplate; harmless but obsolete convention |

### Source findings

| File | Issue |
|------|-------|
| `main.m` | Calls deprecated `NSApplicationMain`; modern template uses `@main` / `NSApplication` launch cycle |
| `pppoeGUI.m` | Manual retain/release everywhere (`alloc/init` without release paths, `[alert release]`, `[queue release]`); leaks `NSString* result`/`all`/`updateAction` HTML string; `NSInformationalAlertStyle` deprecated (macOS 10.12, use `NSAlertStyleInformational`); `setAlertStyle` deprecated (use `alertStyle`); `NSOnState/NSOffState` deprecated (macOS 12, use `NSControlStateValueOn/Off`); `initWithHTML:documentAttributes:` deprecated (macOS 13.0, use `initWithHTML:baseURL:options:documentAttributes:` variant or fallback); `false`/`true` passed to `setEnabled:` and `setState:` (should be `NO`/`YES`); `queue` not nil after dealloc; `applicationWillTerminate` never wired (File's Owner in nib points to `pppoeGUI` but delegate outlet may not be connected) |
| `pppoeOperation.m` | Missing `#include <string.h>` (uses `strlen`, `memcpy` — implicit-function-decl is an **error** in modern clang); `strlen(dialData.sName)` called when `sName` may be NULL ( initWithData allows NULL sName but `main` calls `strlen` unconditionally at line 473); `xstrdup` int-overflow theoretical; `pppoeInterfaceNum` global defined in .m but declared nowhere extern — fine; `[super dealloc]` manual memory; `dialData.cmd`/`connectType` uninitialized copies OK |
| `Info.plist` | No `LSMinimumSystemVersion`; no `NSHighResolutionCapable`; `NSAllowsArbitraryLoads` ATS exception (update-check HTTP URL — acceptable, could note); no `LSApplicationCategoryType`; `CFBundleShortVersionString` missing (modern requirement); `CFBundleExecutable` uses `${EXECUTABLE_NAME}` (still valid) |
| Nibs | `MainMenu.nib` (designable.nib XML + keyedobjects.nib binary plist). Loadable by modern AppKit; no 32-bit assumption. No xib conversion needed for this pass |
| Frameworks | Cocoa, Security, SystemConfiguration — all present and arm64-native on modern macOS. No changes needed |

### Toolchain verification

Host: Xcode 27.0 (27A266a), macOS 27.2. `clang` compiles ObjC with ARC; `xcodebuild` resolves the project (legacy schema auto-upgrades on open). No dependency manager (CocoaPods/SPM) needed — only system frameworks.

## Migration Strategy

1. **Build config modernization** — update `project.pbxproj` in place: `SDKROOT = macosx` (always-latest), `MACOSX_DEPLOYMENT_TARGET = 11.0`, `ARCHS = $(ARCHS_STANDARD)` (arm64 + x86_64), remove `VALID_ARCHS`/`GCC_MODEL_TUNING`/`ZERO_LINK`/`PREBINDING`/`COPY_PHASE_STRIP`/`GCC_ENABLE_FIX_AND_CONTINUE`/`GCC_DYNAMIC_NO_PIC`, fix bundle ID to `com.cppfun.pppoeclient`, add `CODE_SIGN_STYLE = Automatic`, `ENABLE_HARDENED_RUNTIME = YES`, `DEVELOPMENT_TEAM` left empty (ad-hoc for local build).
2. **Info.plist modernization** — add `LSMinimumSystemVersion` (11.0), `NSHighResolutionCapable` true, `CFBundleShortVersionString` 1.1, `LSApplicationCategoryType public.app-category.utilities`.
3. **ARC migration** — enable `CLANG_ENABLE_OBJC_ARC = YES` project-wide; strip manual `retain`/`release`/`autorelease`/`dealloc` from both classes; fix the singleton pattern (dispatch once or class-level).
4. **Deprecated API sweep** — `NSAlertStyleInformational`, `alertStyle` setter, `NSControlStateValueOn/Off`, modern NSAttributedString HTML API, `NSApplicationMain` → programmatic launch.
5. **Correctness fixes** — `#include <string.h>`; NULL-guard `sName`; guard `strlen(NULL)`.
6. **Hardening** — `ENABLE_TESTABILITY`, `GCC_TREAT_WARNINGS_AS_ERRORS` on default set, remove `printf` debug spam from operation path (keep in Debug config via `DEBUG=1` macro guard or keep as-is for CLI-style logging).

No Homebrew, submodules, or pkg-config needed — system frameworks only. Old nib retained (loads fine; conversion to xib/storyboard is cosmetic and out of scope for the functional arm64 port).

## Sub-agent task graph

```
Task 1: pbxproj modernization ──┐
Task 2: Info.plist ─────────────┼──> Task 4: native arm64 build + warning fixes
Task 3: source ARC/deprecated ─┘            │
                                           v
                                 Task 5: verification harness (arch check, launch smoke test, otool deps)
                                           │
                                           v
                                 Task 6: Conventional Commits + PR body
```

Tasks 1-3 are independent file edits (parallel dispatch). Task 4-5 sequential on this host. Task 6 final.

## Acceptance Criteria

1. `xcodebuild -project PPPoEClient.xcodeproj -scheme... -configuration Release` builds with **zero warnings** (modulo SDK deprecation noise) natively on arm64.
2. `file` / `lipo -archs` on built binary shows `arm64`.
3. App launches without crash on this host (smoke test via `open` or direct exec with short timeout kill).
4. `otool -L` shows only system frameworks.
5. All commits Conventional Commits; PR body covers summary/verification/compat notes.

## Backward Compatibility Notes

- Deployment target 11.0 (Big Sur) — first Apple Silicon macOS; keeps Intel Mac users on 11+ covered via universal binary.
- `x86_64` kept in `ARCHS_STANDARD` so old Intel Macs still run the binary.
- Manual-retain-release behavior preserved functionally by ARC; singleton semantics unchanged.
- Update-check URL `http://dev.cppfun.com/pppoe.txt` is dead (2016 domain); ATS exception kept but check disabled gracefully on failure (already logs and ignores).