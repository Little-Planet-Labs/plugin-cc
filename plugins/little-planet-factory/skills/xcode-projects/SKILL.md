---
name: xcode-projects
description: How Little Planet Factory agents work in Xcode and Swift projects (iOS, macOS, watchOS, visionOS; .xcodeproj, .xcworkspace, Swift packages, XcodeGen or Tuist) — detecting how the project is defined, building and testing with xcodebuild from the command line, simulator etiquette, what not to touch (signing, project generation, pbxproj), and how to split Apple-platform work across agents, sequencing units that build together. Use when planning, implementing, or reviewing changes in a project containing an .xcodeproj, .xcworkspace, Package.swift, project.yml, or Project.swift.
user-invocable: false
---

# Xcode projects

## Find out how the project is defined

The first question is which file is the source of truth for the project structure. Getting it wrong means edits that vanish on the next generate, or a corrupted project.

- **XcodeGen** (`project.yml`) or **Tuist** (`Project.swift`, `Tuist/`). The `.xcodeproj` is generated, and often gitignored. Never edit `project.pbxproj`. Change the spec, then regenerate (`xcodegen generate`, `tuist generate`). Targets, settings, dependencies, and file membership all live in the spec.
- **Swift package only** (`Package.swift`, no `.xcodeproj`). Use `swift build` and `swift test`, or `xcodebuild` with the package's scheme when platform-specific SDKs are involved.
- **Hand-maintained `.xcodeproj`.** Check whether it uses folder-synchronized groups: `grep -c PBXFileSystemSynchronizedRootGroup <proj>/project.pbxproj`. If it does, files added under a synchronized folder join the target automatically. If it doesn't, a new source file must be registered in `project.pbxproj` (file reference, group entry, build-file entry, and target sources phase). Prefer a tool the project already uses for that, such as the `xcodeproj` gem or a script. If you have to hand-edit, copy the structure of an existing entry exactly, with new unique IDs, and confirm the project still opens with `xcodebuild -list -scheme <any shared scheme> -derivedDataPath <your DerivedData path>`.
- **Workspace** (`.xcworkspace`, usually alongside CocoaPods or multiple projects). Build with `-workspace`, not `-project`.

Then list what's buildable. Shared scheme names are in `<proj>.xcodeproj/xcshareddata/xcschemes` (or the workspace's). `xcodebuild -list -scheme <any of them> -derivedDataPath <your DerivedData path>` (with `-workspace` or `-project`) then gives every scheme, target, and configuration. Pick the scheme that matches the change, and note any test plan (`.xctestplan`) the scheme uses.

Put what you found in every brief: the project definition, the scheme, the destination, the DerivedData path as an exact absolute path (`main` or an assigned slot, see DerivedData below), the `-jobs` value, and the exact build and test commands. That includes every brief whose agent may build or run tests: workers, managers, inspectors, and researchers.

## Build and test from the command line

Never open Xcode or launch the app on the user's behalf unless they ask. Verification runs through `xcodebuild`, which exits when it's done. A test target with a host app launches that app, so on the Mac it runs as the user's real app; see Choosing a test destination.

```
taskpolicy -c utility nice -n 10 xcodebuild build \
  -scheme <Scheme> \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath <root>/main \
  -jobs <jobs> \
  CODE_SIGNING_ALLOWED=NO

# <destination>: 'platform=iOS Simulator,id=<UDID>', or a Mac destination where allowed (see below)
set -o pipefail
taskpolicy -c utility nice -n 10 xcodebuild test \
  -scheme <Scheme> \
  -destination '<destination>' \
  -derivedDataPath <root>/main \
  -jobs <jobs> \
  -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  -only-testing:<TestTarget>/<TestClass> 2>&1 | tee <scratch>/<run>.log
```

- **Every `xcodebuild` command passes `-derivedDataPath`**, including `-showBuildSettings` and `-showdestinations` (both with `-scheme`), with the exact absolute path your brief names. `-list` needs `-scheme` alongside it (without one it rejects the flag), so use a bare `-list` only when there's no shared scheme; it writes logs and package-resolution state to the default folder. `-downloadPlatform` writes no DerivedData and is exempt. The path is `<root>/main`, as above, or your assigned slot. Never build without it. The default is the same folder the user's open Xcode uses, so building there can fail either side with `unable to attach DB ... build.db: database is locked` and throws away each other's incremental state. If your brief names no DerivedData path, ask your lead or report it. Don't fall back to the default or pick a folder yourself.
- **Run at low priority, with capped parallelism.** Prefix every `xcodebuild` and `swift build`/`swift test` with `taskpolicy -c utility nice -n 10`, so the user's own work and Xcode stay responsive. Keep it on the command's first line, as the template does. The prefix clamps the process tree to utility QoS and lowers its niceness, and it reaches the compilers (measured on Xcode 27: `xcodebuild`'s own `SWBBuildService` child, `swift-frontend`, `clang`, `ld`, and the macOS `xctest` runner all ran at nice 10, priority 20). It does **not** reach anything launchd starts: the simulator runtime, a test host app running in a simulator, `testmanagerd`, or the Xcode app's own build service. A clamped build can take noticeably longer while the machine is busy; that's the trade. `nice` alone barely moves the compilers, so keep both.
- **`-jobs <jobs>`** caps concurrent build tasks (by default `xcodebuild` runs one compiler per core). All agent builds in a session share a budget of half the cores: every `xcodebuild`, `swift build`, and `swift test`, the lead's in `main` and inspectors' and researchers' included. The lead (or you, when there's none) computes it once, `echo $(( $(sysctl -n hw.ncpu) / 2 ))`, using 1 if that prints 0. `<jobs>` in every brief is the budget divided by N (see Slots), rounded down. For `swift build` and `swift test` the flag is `--jobs <jobs>`.
- **Compile-only checks** use a generic destination (`generic/platform=iOS Simulator`, `platform=macOS`), so no simulator needs to boot.
- **Tests** without a host app run on the Mac; see Choosing a test destination below. A simulator boots a whole iOS runtime outside the priority clamp.
- **Scope tests** with `-only-testing:` for workers, and pass `-parallel-testing-enabled NO` so a single test class doesn't spread across cloned simulators. For `swift test`, the equivalents are `--filter <TestTarget>.<TestClass>` and `--no-parallel`. The lead runs the scheme's full tests on the integrated change, with the scheme's own parallel setting and the destination the project's CI or test plan uses, when one is defined. The hosted-test rule below applies to that run too: a Mac destination from CI or a test plan is used only for host-free targets, or with the opt-in or the user's yes (step 2).
- **Every `xcodebuild test` passes `-collect-test-diagnostics never`**, including the lead's full runs and inspectors' runs. By default a failing run collects a sysdiagnose through `simctl diagnose` after its tests finish, and that step can hang for its full 600-second timeout while `xcodebuild` never exits. Anything waiting on the exit waits with it, including the restore of temporary edits (see Temporary edits to source). Measured on Xcode 27: without the flag, runs whose last test had finished stayed alive about 10 minutes in `simctl diagnose`; with it, a failing run exited 3 seconds after `** TEST FAILED **`. Mutation checks and red-first tests fail on purpose, so they always hit this. When you need structured failure detail, `-resultBundlePath` still records it.
- **Read failures from the output, and keep the evidence.** Tee the full output to a log under your scratch directory, as the template does. The template sets `set -o pipefail` before the pipeline; without it, the pipe hides `xcodebuild`'s exit status and a failing run can be reported as successful. Quote the log's `Test run with …` and `** TEST … **` lines in your report. Grep the log, or pipe the live stream through `xcbeautify` if it's installed, to cut the noise. Don't use `-quiet` for a run you'll cite: it prints nothing on success, so its log proves nothing. Add `-resultBundlePath` under your scratch directory when you need structured failure detail, and list the `.xcresult` bundle's absolute path in your report. Don't delete it; the overseer decides. The first `error:` line matters more than the final `** BUILD FAILED **`.
- **Swift packages** resolve on the first build. If resolution fails, run `xcodebuild -resolvePackageDependencies` once, with the same `-derivedDataPath`, and report it if it still fails. Don't delete `Package.resolved` to make it go away.

### Choosing a test destination

First find out whether the test target has a host app. Only the `test` action lists test targets, so run `xcodebuild test -showBuildSettings -scheme <Scheme> -derivedDataPath <path> | grep -E '^Build settings for|PRODUCT_TYPE =|TEST_HOST ='`, and classify each target by its `PRODUCT_TYPE`:

- `com.apple.product-type.bundle.ui-testing` is always hosted. UI tests have no `TEST_HOST`; they launch the app named by `TEST_TARGET_NAME`.
- `com.apple.product-type.bundle.unit-test` with a `TEST_HOST =` line is hosted.
- `com.apple.product-type.bundle.unit-test` without one is host-free.
- Any other product type (the app, frameworks) isn't a test target; ignore it.

Swift package tests are host-free.

Then, for an agent's scoped test run:

1. **Host-free tests run on the Mac.** `swift test` for a package with no platform-specific SDKs, otherwise `xcodebuild test -destination 'platform=macOS'`, or a Mac variant from step 3 when the target builds only for iOS.
2. **Hosted tests run on a simulator**, unless the project's `CLAUDE.md` opts in with this line under an `## Xcode` heading:
   ```
   mac-hosted-tests: allowed
   ```
   On the Mac, the host app runs under the user's account, with a window, their sandbox container, UserDefaults, Keychain, and signed-in iCloud, so tests could change or sync real data. Designed for iPad also installs the app. Without the line, never run a hosted test on a Mac destination, except with the user's yes for this task, below. If there's no simulator destination either, as in a macOS-only app, ask the user each time before running hosted or UI tests on the Mac. Only the overseer asks, as an interview question that says in one line that the tests run as the real app with their data, and names `mac-hosted-tests: allowed` as the `CLAUDE.md` line that stops the question; other agents don't run those tests and report them to their lead as a question for the user. A yes allows the Mac run for that task only; a no means they're reported as unverified.
3. **Mac destinations**, for host-free tests or with the opt-in or the user's yes (step 2). Use one only if `xcodebuild -showdestinations -scheme <Scheme> -derivedDataPath <path>` already lists it:
   - A macOS target → `-destination 'platform=macOS'`.
   - `variant:Mac Catalyst` → `-destination 'platform=macOS,variant=Mac Catalyst'`.
   - `variant:Designed for [iPad,iPhone]` → `-destination 'platform=macOS,variant=Designed for iPad'`. Don't copy the bracketed form; the comma breaks parsing (`unreadable input 'iPhone]'`). This destination installs the app on the Mac, so it needs the project's own development signing: don't pass `CODE_SIGNING_ALLOWED=NO` (install fails with `its integrity could not be verified`) or `-allowProvisioningUpdates`. If it fails on signing or provisioning, use a simulator; that includes host-free, iOS-only test bundles on this destination.
4. **Simulators.** Pick one that isn't booted, by UDID from `xcrun simctl list devices available`, not by name, because names repeat across runtimes. Don't boot it with `xcrun simctl boot`; `xcodebuild test` boots it.

Never change supported platforms or destinations, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, Catalyst settings, or signing to make a Mac destination appear. Some tests need the simulator: UIKit-only or device-behavior APIs, simulator state, and tests that fail only on the Mac variant. When a Mac run fails for platform reasons rather than because of the change, rerun on a simulator and say so in your report. Don't change tests to make them pass on the Mac.

### Environment failures, not code failures

Some failures come from the machine rather than the change. Recognize them and report them as environmental:

- **SDK and simulator runtime mismatch after an Xcode update**: no matching destinations, `No simulator runtime version…`, or asset catalog compilation (`actool`) failing. The new Xcode's SDK has no installed runtime. `xcodebuild -downloadPlatform iOS` (or the platform in question) installs it. That download is large and changes the machine, so ask before running it.
- **A companion platform's runtime is missing** (for example watchOS for an iOS app with an embedded watch app). The whole scheme can refuse to resolve even though the target you changed is fine. Build the specific target, or type-check against the right SDK, and say that the full scheme couldn't be built.
- **Signing and provisioning errors on a simulator build** usually mean signing wasn't disabled for the check. Add `CODE_SIGNING_ALLOWED=NO` to compile-only builds rather than touching the project's signing settings. Hosted test runs keep the project's own simulator signing: an unsigned host app has no entitlements, and one that opens iCloud, CloudKit, or an App Group at launch can trap before the runner connects (`Early unexpected exit, operation never finished bootstrapping … The test runner crashed before establishing connection`). If a hosted run fails that way, drop `CODE_SIGNING_ALLOWED=NO` before calling it environmental.
- **Tests finished but `xcodebuild` doesn't exit.** The log's last `Test run with …` line is there, and minutes pass with no `** TEST … **` line. Check for a `simctl diagnose` child (see Finding processes below). A run that passed `-collect-test-diagnostics never` shouldn't reach this. If one does, restore any temporary source edits first, then end only the `xcodebuild` PID you recorded when you started it and its `simctl diagnose` (see Finding processes for how to prove ownership), and report it. Never wait on it.
- **Framework APIs that exist only on a device SDK** can't be compiled for or tested on the simulator. Say what couldn't be verified.
- **Stale state in `main`**: errors the change can't explain, such as `cannot find type X in scope` from a leftover `.swiftmodule`, or products built before a deployment-target change. Report it. The overseer rebuilds in a fresh slot, or asks the user before clearing `main`. Agents never clear it themselves.

### Temporary edits to source

Mutation checks, and red-first proofs of a fix, change source files, build, test, and put the files back. While those edits are on disk, every build that reads the working tree compiles them. That includes another agent's build in its own slot.

- **Only when you're the tree's only builder.** Ask your lead to schedule the run, and don't start it while any other agent's `xcodebuild`, `swift build`, or `swift test` is reading the same working tree. A slot gives each builder its own DerivedData, not its own sources.
- **One command owns the edit.** Back up each file, apply the change, run the build and test, and restore, all in one script. The script restores through a `trap` on `EXIT`, `INT`, and `TERM`, so a killed or failed run still restores. Launch `xcodebuild` backgrounded on its own, with output redirected to the log rather than piped to `tee` (`taskpolicy … xcodebuild test … > <log> 2>&1 &`), so `pid=$!` right after is the build itself; follow the log separately (`tail -f <log>` or polling the file), and take the run's pass or fail from `wait $pid`, not from a pipeline's exit status. That's the same PID the guard ends if the run hangs (see Finding processes). Verify each file afterwards with `cmp` against its backup, and report that it matches.
- **Don't wait on `xcodebuild` to exit.** Pass `-collect-test-diagnostics never` (the run fails by design). Watch the log, and once the final `Test run with …` or `** TEST … **` line appears, restore, even if `xcodebuild` is still alive. If the log stops growing for about 10 minutes, restore and end the `xcodebuild` PID you recorded and its `simctl diagnose`; see Finding processes for how to prove ownership.
- **One batch at a time.** Start the next batch only after the previous run's `xcodebuild` has exited and the restore is verified.

### Watching for stalls (lead)

Agents wait on processes, and a stuck process leaves them waiting without saying so. While agents are building, the overseer (or the main session) runs a watchdog in the background. It's a loop that exits, which wakes the lead, when a condition holds:

- an `xcodebuild` that is this session's — its `-derivedDataPath` is one of this session's slot paths, or it's in `main` and the lead recorded its PID when it started that build — has run longer than the slowest expected run, for example 30 minutes; or
- a `simctl diagnose` has run longer than 2 minutes; or
- nothing has built and nothing in the working tree has changed for about 25 minutes while agents are still running.

Another session's build sitting in `main` is never this watchdog's business: a shared `-derivedDataPath` alone doesn't make it this session's. It finds processes by executable name (see Finding processes). It only ever wakes the lead about a stuck `xcodebuild`; it never ends one. It ends a stuck process only when it can prove the process is one this session started: a `simctl diagnose` on one of the session's own simulator UDIDs, never one on the user's simulator. It reports everything else, and never matches or signals shells. After it exits, the lead reads what it found, acts, and starts it again.

## DerivedData

Two `xcodebuild` processes sharing a DerivedData folder contend for its build database and fail with locking errors. Xcode's default folder is shared with the user's open Xcode, so agents never build there.

- **The agent DerivedData root** is one per repository, outside scratch because scratch is per session and cleared on reboot. It's computed from the main repository, so every worktree shares it; a submodule or separate git dir falls back to its own top level:
  ```
  top=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && case $top in */.git) top=$(dirname "$top") ;; *) top=$(git rev-parse --show-toplevel) ;; esac || top=$(pwd)
  echo "$HOME/Library/Developer/Xcode/DerivedData-agents/$(basename "$top" | tr -c 'A-Za-z0-9._\n-' '_')-$(printf %s "$top" | shasum | cut -c1-8)"
  ```
  It holds `main` and `sessions/<session-id>/slot-N`. Use the absolute path it prints, never `~`, which isn't expanded inside the quoted `pgrep` patterns below. A unit working in a worktree still builds in `main` or this session's slots under this root, never in a folder inside the worktree.
- **Time Machine.** In each session, before its first build, the overseer (or the main session) runs `mkdir -p` on `$HOME/Library/Developer/Xcode/DerivedData-agents` as an absolute path, then `tmutil isexcluded` on it. Unless that prints `[Excluded]`, it runs `tmutil addexclusion` on it (no `-p`, no sudo) and notes it in the cleanup record. If `tmutil addexclusion` fails, report it and continue. It's the one machine setting agents change without asking.
- **Checking that a folder is free.** `pgrep -fl -- "-derivedDataPath <folder>/?( |\$)"` exits 1 when nothing is building there. Treat any other exit status, 0 or an error, as busy. The anchored end keeps `main` from matching `main-old`, and `slot-1` from matching `slot-10`. `pgrep -f` also matches a shell whose command line merely contains that text, including the one running the check, so a match can be a false "busy". That's safe for this check, which only ever waits, but never use `pgrep -f` to pick a process to kill; see Finding processes.
- **Finding processes to act on.** Match by executable name, then read the arguments. For example, `for p in $(pgrep -x xcodebuild); do ps -o args= -p $p; done`, filtered on your `-derivedDataPath`; or `pgrep -x simctl`, filtered on ` diagnose ` and your simulator's UDID. `pgrep -f '<pattern>'` also matches any shell, script or agent command whose text contains the pattern, so killing what it returns can end another agent's build or guard script mid-run. `-derivedDataPath` alone doesn't prove ownership: `main` is shared by every session, so an `xcodebuild` running there could be another session's. Establish ownership before acting: a builder that may need to end its own `xcodebuild` launches it backgrounded on its own, with output redirected to its log rather than piped to `tee` (`taskpolicy … xcodebuild test … > <log> 2>&1 &`), and takes `pid=$!` right after — that's the `xcodebuild` process itself, and it's what gets ended and reported. `$!` after a backgrounded pipeline (`xcodebuild … | tee … &`) is the last process in the pipeline, `tee`, not `xcodebuild`, so never use it to find the build. A `-derivedDataPath` under this session's slots corroborates a recorded PID; a path under `main` alone does not.
- **`main`** is shared by every session on the repo and persists, so builds stay warm. The overseer's own builds, and a lone or sequential builder, use it once the check exits 1. If it's busy, or a build fails with `database is locked` because another session started at the same moment, that's environmental: the overseer switches to one of its slots, and any other agent reports it to its lead rather than picking a folder.
- **Session ID.** Use `$CLAUDE_CODE_SESSION_ID`, falling back to the name of the scratch directory's parent, and check it's one UUID-like path component:
  ```
  sid=${CLAUDE_CODE_SESSION_ID:-$(basename "$(dirname "<scratch dir>")")}
  printf %s "$sid" | grep -Eqx '[0-9A-Fa-f-]{32,36}' && echo "$sid"
  ```
  If it prints nothing, run `uuidgen` once, write the result to `<scratch dir>/session-id`, read it from there for the rest of the session, and say so in the cleanup record. Never build directly under `sessions/`.
- **Slots.** Only the overseer (or the main session when there is none) creates `<root>/sessions/<session-id>/` and its slots, and no other session touches them. It gives each concurrent builder a slot by absolute path. At planning, the lead sets N, the most agents that will build at once, counting its own `main` builds: at most 2 unless the overseer has measured that the machine handles more, and never more than the budget. Never lower N mid-session. To raise it, wait until no agent that may build is running (managers included) and the lead's own builds have finished, and the free-folder check exits 1 for `main` and every session slot and `pgrep -f 'swift-(build|test)'` exits 1, then give the new `<jobs>` in each later brief or resume. A manager hands out only the slots and `<jobs>` in its brief, and uses `main` itself only when its brief says so, which the overseer counts in N. Keep the same slot across repair rounds and re-inspections, and never create a folder per agent or per round. A slot is free for another agent once its holder has reported back or been stopped, and the check exits 1.
- **Cleanup.** Only the overseer deletes build output. Every other agent lists what it created in its report as absolute paths, including `-resultBundlePath` bundles and any folder the brief didn't assign, and a manager passes its agents' lists up. The overseer deletes `<root>/sessions/<session-id>` as one path once `pgrep -fl -- "-derivedDataPath <root>/sessions/<session-id>/"` exits 1, following the limits in its Cleanup section. It never deletes `main`, the root, `<root>/sessions`, or another session's directory. A crashed session leaves its directory behind, so the overseer lists `sessions/*` directories that are older than a few days and idle by the same check, and the user decides.

## Simulator etiquette

The user may have a simulator open for their own work.

- Never target the simulator the user is using, and never run `xcrun simctl shutdown all`, `erase all`, or `delete unavailable`. Those hijack or destroy the user's session. Check `xcrun simctl list devices booted` first.
- For tests, use a simulator that isn't booted. If the project's test setup needs a dedicated device, create one (`xcrun simctl create`), use it, and say so in the report.
- Don't pre-boot with `xcrun simctl boot`. After the run, if the device you used is still booted and was shut down before you started, or you created it, run `xcrun simctl shutdown <UDID>`. Never shut down a device that was already booted.
- Don't erase a simulator or change its settings, locale, or accounts unless the brief calls for it. Tests that depend on simulator state (iCloud sign-in, permissions, locale) are an environmental precondition to report, not something to force.

## What not to touch

Unless the brief explicitly asks, leave these alone. They affect distribution, other machines, and CI:

- Signing: development team, code-sign identity, provisioning profiles, `CODE_SIGN_STYLE`.
- Bundle identifiers, entitlements files, App Groups, capabilities, and `Info.plist` privacy strings (a missing usage string crashes the app at runtime, and a changed one can fail review).
- Deployment targets, `SWIFT_VERSION`, Swift language mode, and strict-concurrency level. Raising any of them changes what compiles for everyone.
- Build configurations and scheme settings shared through `xcshareddata`.
- CI scripts (`ci_scripts/`, Fastlane) and version or build numbers.

If the right fix needs one of these, stop and report what you need.

## Swift code

- Match the project's Swift language mode and concurrency posture. In Swift 6 mode or with strict concurrency, fix `Sendable` and actor-isolation errors properly — isolate to `@MainActor`, make the type `Sendable`, or restructure — rather than with `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` imports, unless the codebase already uses that escape for the same case.
- UI code runs on the main actor. Don't block it with synchronous I/O or long work.
- Follow the existing architecture (SwiftUI versus UIKit or AppKit, the view-model pattern, dependency injection, persistence layer). SwiftUI views stay small, and state lives where the project's pattern puts it (`@State`, `@Observable` models, environment).
- String catalogs (`.xcstrings`) are updated by Xcode's build, not written back by `xcodebuild`. When you add a user-facing string, add its entry to the catalog yourself if the project keeps them there.
- Don't force-unwrap or `try!` outside tests unless the neighboring code establishes it for that case.

## Splitting Apple-platform work across agents

- **What builds together.** An app scheme compiles the app target and every target it depends on from source, so units anywhere in one app, its in-tree frameworks, or the local packages it builds all build together and run one after another. Two Swift packages each checked with its own `swift build`/`swift test`, or schemes that don't include each other, don't. Every test run builds its target.
- **`project.pbxproj` is one file for the whole project.** In a hand-maintained project, only one unit edits it, or the lead does during integration. Other units create their files on disk and report which target each belongs to. With XcodeGen or Tuist, the same applies to the spec file and to running the generator.
- **Concurrent builds need separate DerivedData.** The overseer assigns slots; see DerivedData above.
- **Concurrent tests need separate simulators.** Give each unit its own device UDID, or have only the lead run tests.
- `Package.swift`, `Package.resolved`, shared asset catalogs, `Info.plist`, entitlements, and localization catalogs each have one owner.

A good split follows module or feature boundaries — a Swift package, a framework target, or a screen and its view model — with shared protocols and model types fixed in the briefs before dispatch.

## Review focus

Inspecting Apple-platform changes, weight these: edits to generated project files instead of their spec; new files not added to a target (they compile nowhere and the build still passes); main-thread blocking and actor-isolation escapes; retain cycles in closures and delegates (a missing `[weak self]` where the closure outlives the call); force unwraps on external data; missing `Info.plist` usage strings for new permission use; and unrequested changes to signing, deployment targets, or build settings.
