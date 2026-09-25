---
name: xcode-projects
description: How Little Planet Factory agents work in Xcode and Swift projects (iOS, macOS, watchOS, visionOS; .xcodeproj, .xcworkspace, Swift packages, XcodeGen or Tuist) — detecting how the project is defined, building and testing with xcodebuild from the command line, simulator etiquette, what not to touch (signing, project generation, pbxproj), and how to split Apple-platform work across parallel agents. Use when planning, implementing, or reviewing changes in a project containing an .xcodeproj, .xcworkspace, Package.swift, project.yml, or Project.swift.
user-invocable: false
---

# Xcode projects

## Find out how the project is defined

The first question is which file is the source of truth for the project structure. Getting it wrong means edits that vanish on the next generate, or a corrupted project.

- **XcodeGen** (`project.yml`) or **Tuist** (`Project.swift`, `Tuist/`). The `.xcodeproj` is generated, and often gitignored. Never edit `project.pbxproj`. Change the spec, then regenerate (`xcodegen generate`, `tuist generate`). Targets, settings, dependencies, and file membership all live in the spec.
- **Swift package only** (`Package.swift`, no `.xcodeproj`). Use `swift build` and `swift test`, or `xcodebuild` with the package's scheme when platform-specific SDKs are involved.
- **Hand-maintained `.xcodeproj`.** Check whether it uses folder-synchronized groups: `grep -c PBXFileSystemSynchronizedRootGroup <proj>/project.pbxproj`. If it does, files added under a synchronized folder join the target automatically. If it doesn't, a new source file must be registered in `project.pbxproj` (file reference, group entry, build-file entry, and target sources phase). Prefer a tool the project already uses for that, such as the `xcodeproj` gem or a script. If you have to hand-edit, copy the structure of an existing entry exactly, with new unique IDs, and confirm the project still opens with `xcodebuild -list`.
- **Workspace** (`.xcworkspace`, usually alongside CocoaPods or multiple projects). Build with `-workspace`, not `-project`.

Then list what's buildable. `xcodebuild -list` (with `-workspace` or `-project`) gives the schemes, targets, and configurations. Pick the scheme that matches the change, and note any test plan (`.xctestplan`) the scheme uses.

Put what you found in every brief: the project definition, the scheme, the destination, and the exact build and test commands.

## Build and test from the command line

Never open Xcode or launch the app on the user's behalf unless they ask. Verification runs through `xcodebuild`, which exits when it's done.

```
xcodebuild build \
  -scheme <Scheme> \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath <scratch>/DerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -scheme <Scheme> \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath <scratch>/DerivedData \
  -only-testing:<TestTarget>/<TestClass>
```

- **Compile-only checks** use a generic destination (`generic/platform=iOS Simulator`, `platform=macOS`), so no simulator needs to boot.
- **Tests** need a concrete simulator. Pick one by UDID from `xcrun simctl list devices available`. Don't pick by name alone, because names repeat across runtimes.
- **Scope tests** with `-only-testing:` for workers. The lead runs the scheme's full tests on the integrated change.
- **Read failures from the output.** Pass `-quiet`, or pipe through `xcbeautify` if it's installed, to cut the noise. Add `-resultBundlePath` when you need structured failure detail. The first `error:` line matters more than the final `** BUILD FAILED **`.
- **Swift packages** resolve on the first build. If resolution fails, run `xcodebuild -resolvePackageDependencies` once and report it if it still fails. Don't delete `Package.resolved` to make it go away.

### Environment failures, not code failures

Some failures come from the machine rather than the change. Recognize them and report them as environmental:

- **SDK and simulator runtime mismatch after an Xcode update**: no matching destinations, `No simulator runtime version…`, or asset catalog compilation (`actool`) failing. The new Xcode's SDK has no installed runtime. `xcodebuild -downloadPlatform iOS` (or the platform in question) installs it. That download is large and changes the machine, so ask before running it.
- **A companion platform's runtime is missing** (for example watchOS for an iOS app with an embedded watch app). The whole scheme can refuse to resolve even though the target you changed is fine. Build the specific target, or type-check against the right SDK, and say that the full scheme couldn't be built.
- **Signing and provisioning errors on a simulator build** usually mean signing wasn't disabled for the check. Add `CODE_SIGNING_ALLOWED=NO` rather than touching the project's signing settings.
- **Framework APIs that exist only on a device SDK** can't be compiled for or tested on the simulator. Say what couldn't be verified.

## Simulator etiquette

The user may have a simulator open for their own work.

- Never target the simulator the user is using, and never run `xcrun simctl shutdown all`, `erase all`, or `delete unavailable`. Those hijack or destroy the user's session. Check `xcrun simctl list devices booted` first.
- For tests, use a simulator that isn't booted. If the project's test setup needs a dedicated device, create one (`xcrun simctl create`), use it, and say so in the report.
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

- **`project.pbxproj` is one file for the whole project.** In a hand-maintained project, only one unit edits it, or the lead does during integration. Other units create their files on disk and report which target each belongs to. With XcodeGen or Tuist, the same applies to the spec file and to running the generator.
- **Concurrent builds need separate DerivedData.** Two `xcodebuild` processes sharing a DerivedData folder contend for its build database and fail with locking errors. Give every agent that builds its own `-derivedDataPath` under its scratch directory.
- **Concurrent tests need separate simulators.** Give each unit its own device UDID, or have only the lead run tests.
- `Package.swift`, `Package.resolved`, shared asset catalogs, `Info.plist`, entitlements, and localization catalogs each have one owner.

A good split follows module or feature boundaries — a Swift package, a framework target, or a screen and its view model — with shared protocols and model types fixed in the briefs before dispatch.

## Review focus

Inspecting Apple-platform changes, weight these: edits to generated project files instead of their spec; new files not added to a target (they compile nowhere and the build still passes); main-thread blocking and actor-isolation escapes; retain cycles in closures and delegates (a missing `[weak self]` where the closure outlives the call); force unwraps on external data; missing `Info.plist` usage strings for new permission use; and unrequested changes to signing, deployment targets, or build settings.
