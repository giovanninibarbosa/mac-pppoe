# PPPoE arm64 Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build PPPoEClient natively on arm64/macOS 27 with ARC, zero legacy build flags, zero deprecated APIs.

**Architecture:** In-place edit of pbxproj build settings + Info.plist keys + ObjC source (pppoeGUI.m, pppoeOperation.m, main.m). No dependency managers. Nib untouched.

**Tech Stack:** Xcode 27 / clang / Cocoa / SystemConfiguration / Security frameworks.

**Spec:** `MIGRATION_SPEC.md` (root of repo).

## Global Constraints

- `SDKROOT = macosx` (always-latest), `MACOSX_DEPLOYMENT_TARGET = 11.0`, `ARCHS = $(ARCHS_STANDARD)`.
- `PRODUCT_BUNDLE_IDENTIFIER = com.cppfun.pppoeclient`.
- `CLANG_ENABLE_OBJC_ARC = YES` all configs.
- Zero-warnings goal: treat new warnings as errors to fix, not silence.
- Conventional Commits only. Commit after each task.
- Never commit `opencode.json` (local tool config).

---

### Task 1: pbxproj build config modernization

**Files:**
- Modify: `PPPoEClient.xcodeproj/project.pbxproj` (XCBuildConfiguration sections, lines 252-312)

**Interfaces:**
- Produces: project file that `xcodebuild -list` parses without errors; build settings readable by Task 4.

Steps:

- [ ] Edit `C01FCF4B08A954540054247B /* Debug */` (target-level): remove `COMBINE_HIDPI_IMAGES`, `COPY_PHASE_STRIP`, `GCC_DYNAMIC_NO_PIC`, `GCC_ENABLE_FIX_AND_CONTINUE`, `GCC_MODEL_TUNING`, `ZERO_LINK`. Keep `GCC_OPTIMIZATION_LEVEL = 0`, `GCC_PRECOMPILE_PREFIX_HEADER`, `GCC_PREFIX_HEADER`, `INFOPLIST_FILE`, `PRODUCT_BUNDLE_IDENTIFIER`, `PRODUCT_NAME`, `WRAPER_EXTENSION`. Change `PRODUCT_BUNDLE_IDENTIFIER` to `com.cppfun.pppoeclient`. Add `CODE_SIGN_STYLE = Automatic;`.
- [ ] Edit `C01FCF4C08A954540054247B /* Release */` (target-level): remove `COMBINE_HIDPI_IMAGES`, `GCC_MODEL_TUNING`, `VALID_ARCHS`. Change `PRODUCT_BUNDLE_IDENTIFIER` to `com.cppfun.pppoeclient`. Add `CODE_SIGN_STYLE = Automatic;` and `ENABLE_HARDENED_RUNTIME = YES;`.
- [ ] Edit `C01FCF4F08A954540054247B /* Debug */` (project-level): set `ARCHS = "$(ARCHS_STANDARD)";`, remove `ONLY_ACTIVE_ARCH = NO` (keep default YES for Debug), set `MACOSX_DEPLOYMENT_TARGET = 11.0;`, change `SDKROOT = macosx;` (drop `10.11`), remove `PREBINDING`.
- [ ] Edit `C01FCF5008A954540054247B /* Release */` (project-level): set `ARCHS = "$(ARCHS_STANDARD)";`, set `MACOSX_DEPLOYMENT_TARGET = 11.0;`, change `SDKROOT = macosx;`, remove `PREBINDING`.
- [ ] Verify: `xcodebuild -project PPPoEClient.xcodeproj -list` exits 0 and shows target `PPPoEClient`.
- [ ] Commit: `git add PPPoEClient.xcodeproj && git commit -m "build: modernize project settings for arm64 and current SDK"`

### Task 2: Info.plist modernization

**Files:**
- Modify: `Info.plist`

**Interfaces:**
- Consumes: `PRODUCT_BUNDLE_IDENTIFIER = com.cppfun.pppoeclient` from Task 1 (via `$(PRODUCT_BUNDLE_IDENTIFIER)` — no plist edit needed for ID).
- Produces: plist with all keys Task 4's build needs; `LSMinimumSystemVersion = 11.0`.

Steps:

- [ ] Add after `CFBundleSignature`:
```xml
	<key>CFBundleShortVersionString</key>
	<string>1.1</string>
```
- [ ] Add before `CFBundleVersion`:
```xml
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
```
- [ ] Verify: `plutil -lint Info.plist` prints `OK`.
- [ ] Commit: `git add Info.plist && git commit -m "build: add modern Info.plist keys for arm64 deployment"`

### Task 3: Source modernization (ARC + deprecated APIs + correctness)

**Files:**
- Modify: `pppoeGUI.m`, `pppoeGUI.h`, `pppoeOperation.m`, `pppoeOperation.h`, `main.m`

**Interfaces:**
- Consumes: nothing.
- Produces: ARC-clean sources that compile warning-free under Task 4. Public API unchanged: `+[pppoeGUI shared]`, `-initWithData:` (non-ARC callers see no diff).

Steps:

- [ ] **pppoeGUI.m** — remove `[self autorelease]` in `init` singleton (return `shared` when non-nil after discarding duplicate; standard ARC pattern below), remove `dealloc` body (`queue`, `theTimer` handled by ARC; keep `theTimer` invalidate in `dealloc`? No — ARC forbids `[super dealloc]`; keep a `dealloc` that only invalidates the timer, no release calls, no super call).
  Replace init/dealloc/shared with:
```objc
- (instancetype)init {
	if (shared) {
		return shared;
	}
	self = [super init];
	if (self) {
		queue = [[NSOperationQueue alloc] init];
		tStatus = kConnectTitle;
		pppStatus = kPPPDisconnect;
		theTimer = nil;
		shared = self;
	}
	return self;
}

- (void)dealloc {
	[theTimer invalidate];
}

+ (instancetype)shared {
	static dispatch_once_t onceToken;
	static pppoeGUI* sharedInstance;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[pppoeGUI alloc] init];
	});
	return sharedInstance;
}
```
  Note: keep ivar `shared` used by `init`? Simpler: delete static `shared` ivar usage — make `init` plain init, `+shared` the only singleton path. Adjust: plain `init` (no singleton check), `+shared` with dispatch_once. `setPPPStatus:` in pppoeOperation references `[pppoeGUI shared]` — still works.
- [ ] **pppoeGUI.m** — `helpAction:`: replace `[alert setAlertStyle:NSInformationalAlertStyle]` with `[alert setAlertStyle:NSAlertStyleInformational]`.
- [ ] **pppoeGUI.m** — `ethernetAction:`/`airportAction:`: `NSOnState` → `NSControlStateValueOn`, `NSOffState` → `NSControlStateValueOff`.
- [ ] **pppoeGUI.m** — `stringFromHTML:`: replace deprecated `initWithHTML:documentAttributes:` call with modern equivalent:
```objc
	NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
	NSAttributedString* string = [[NSAttributedString alloc] initWithHTML:data options:nil documentAttributes:nil];
```
  (`initWithHTML:options:documentAttributes:` is available macOS 10.0+ and not deprecated.)
- [ ] **pppoeGUI.m** — `theTimerControl:`: `[cButton setEnabled:false]` → `setEnabled:NO`, `setEnabled:true` → `setEnabled:YES`.
- [ ] **pppoeGUI.m** — `checkUpdate:` completion handler: nil-check `data` before `initWithData:` (currently `!data` logs but then proceeds to use nil data — harmless under ObjC messaging-nil but fix for clarity: `if (data == nil) return;` after log). Remove unused `result`/`all` leak warnings — under ARC no leak, keep logic.
- [ ] **pppoeGUI.h** — ensure `init` returns `instancetype`; check ivars declared; no change unless `shared` referenced in header.
- [ ] **pppoeOperation.m** — add `#include <string.h>` at top (after `assert.h`).
- [ ] **pppoeOperation.m** — `initWithData:`: change to safe copy; `sName` may be NULL:
```objc
	if (!data->uName) return nil;
	if (!data->pwd) return nil;
	dialData.uName = xstrdup(data->uName);
	dialData.pwd = xstrdup(data->pwd);
	dialData.sName = data->sName ? xstrdup(data->sName) : NULL;
```
- [ ] **pppoeOperation.m** — ARC conversion: remove `dealloc` (free() calls move: keep dealloc but only `free()` — ARC allows custom dealloc without `[super dealloc]`):
```objc
- (void)dealloc {
	free(dialData.uName);
	free(dialData.pwd);
	free(dialData.sName);
}
```
- [ ] **pppoeOperation.m** — `main` line 473: `if (strlen(dialData.sName)>0)` → `if (dialData.sName && strlen(dialData.sName)>0)`.
- [ ] **pppoeOperation.m** — `main` line 509: `SCNetworkConnectionGetStatus(connection)` called even when `connection` NULL — `SCNetworkConnectionGetStatus(NULL)` returns `kSCNetworkConnectionInvalid`; guard to keep current behavior (returns invalid status, both cmd branches handle) — no change needed, verify.
- [ ] **pppoeOperation.h/pppoeGUI.h** — check for `retain`/`release` in headers: none expected.
- [ ] **main.m** — replace `NSApplicationMain` (deprecated macOS 14.0):
```objc
#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		[application setDelegate:[[pppoeGUI alloc] init]];  // only if needed — check nib
		return NSApplicationMain(argc, argv);
	}
}
```
  Wait — `NSApplicationMain` IS the deprecated one. Correct modern form without a delegate class attribute (nib-based):
```objc
#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		return NSApplicationMain(argc, argv);
	}
}
```
  still deprecated. Use `@main`-equivalent programmatic:
```objc
#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		NSBundle *mainBundle = [NSBundle mainBundle];
		NSMenu *mainMenu = [[NSMenu alloc] init];
		// nib supplies menu; load MainMenu nib manually:
		[NSBundle loadNibNamed:@"MainMenu" owner:app];
		[app run];
	}
	return 0;
}
```
  Safest: keep nib loading via `NSApplicationMain` (deprecated but functional) OR programmatic load. Choose programmatic `loadNibNamed` with app as owner; but nib File's Owner may be pppoeGUI/NSObject — inspect nib before choosing. Fallback decision rule: if build emits deprecation warning for `NSApplicationMain`, switch to programmatic; else keep.
- [ ] Verify compile syntax: none standalone (Task 4 does full build).
- [ ] Commit: `git add -A ':!opencode.json' && git commit -m "refactor: adopt ARC and replace deprecated AppKit APIs"`

### Task 4: Native arm64 build + warning fixes

**Files:**
- Modify: any file emitting warnings (expected: none after Task 3).

**Interfaces:**
- Consumes: Tasks 1-3 outputs.
- Produces: `build/Release/PPPoEClient.app` universal (arm64 + x86_64).

Steps:

- [ ] Run: `xcodebuild -project PPPoEClient.xcodeproj -target PPPoEClient -configuration Release build` from repo root; default derived data. Expect success; capture warnings.
- [ ] For each warning: fix source, rebuild. Repeat until zero (SDK deprecation notes acceptable if unavoidable).
- [ ] Also build Debug: `xcodebuild ... -configuration Debug build`.
- [ ] Commit any fixes: `git commit -m "fix: resolve remaining toolchain warnings"` (empty commit only if needed; skip if clean).

### Task 5: Verification harness

**Files:**
- Create: `scripts/verify.sh`

**Interfaces:**
- Consumes: built app from Task 4.
- Produces: exit-0 script proving acceptance criteria (spec section "Acceptance Criteria").

Steps:

- [ ] Create `scripts/verify.sh`:
```bash
#!/bin/bash
set -euo pipefail
APP="$(find ~/Library/Developer/Xcode/DerivedData -name PPPoEClient.app -path '*Release*' -newermt '-1 hour' | head -1)"
[ -n "$APP" ] || { echo "FAIL: app not found in DerivedData"; exit 1; }
echo "== archs =="
lipo -archs "$APP/Contents/MacOS/PPPoEClient"
lipo -archs "$APP/Contents/MacOS/PPPoEClient" | grep -q arm64 || { echo "FAIL: no arm64"; exit 1; }
echo "== deps =="
otool -L "$APP/Contents/MacOS/PPPoEClient"
echo "== codesign =="
codesign -dv "$APP" 2>&1 | head -3
echo "== launch smoke (5s) =="
timeout 5 "$APP/Contents/MacOS/PPPoEClient" && rc=0 || rc=$?
# app runs until quit; timeout kill 124 acceptable
if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 143 ]; then
  echo "FAIL: launch rc=$rc"
  exit 1
fi
echo "PASS"
```
- [ ] `chmod +x scripts/verify.sh && ./scripts/verify.sh` — expect PASS.
- [ ] Commit: `git add scripts/verify.sh && git commit -m "build: add arm64 verification harness"`

### Task 6: Conventional commits audit + PR body

**Files:**
- Create: `PR_DESCRIPTION.md` (repo root, for copy-paste to GitHub; not committed as code — commit it so maintainer sees it? No: upstream PR text goes in PR, keep file untracked or commit under docs/. Decide: commit as `docs/PR_DESCRIPTION.md`.)

**Steps:**

- [ ] `git log --oneline` — verify all commits Conventional (`build:`, `refactor:`, `fix:`).
- [ ] Write `docs/PR_DESCRIPTION.md` with sections: Summary, Verification Results (macOS 27.2 arm64, Xcode 27), Backward Compatibility, Dependency Migration notes.
- [ ] Commit: `git add docs/PR_DESCRIPTION.md && git commit -m "docs: add upstream PR description"`

## Self-Review

- Spec coverage: build config (Task 1), plist (Task 2), source (Task 3), build+warn (Task 4), acceptance harness (Task 5), commits+PR (Task 6). All spec sections mapped.
- Placeholders: main.m launch decision has explicit fallback rule, not TBD. No TODOs elsewhere.
- Type consistency: `NSAlertStyleInformational`, `NSControlStateValueOn` real SDK constants; `dispatch_once` singleton matches `[pppoeGUI shared]` call site in pppoeOperation.m line 360.