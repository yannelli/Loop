# Repository Guide

## Project Shape

- `Loop.xcodeproj/project.pbxproj` is authoritative for current targets and file membership. `.travis.yml`, `Loop.xcscheme`, `DoseMathTests.xcscheme`, and the `Learn/` and `DoseMathTests/` directories contain stale references to targets no longer present in the project.
- The app enters through `Loop/main.swift` -> `AppDelegate` -> `LoopAppManager`. `LoopAppManager` wires application services; `DeviceDataManager` owns device managers, stores, and `LoopDataManager`.
- `LoopCore` is shared domain/framework code, `LoopUI` is shared UI, and `Common` files are compiled into multiple app/extension targets rather than forming a separate module. Check target membership before changing shared files.
- Device, service, and support implementations are runtime `.loopplugin` bundles. The Loop build copies already-built plugins from `BUILT_PRODUCTS_DIR`; this repo does not build those plugin implementations.

## Build And Test

- Build and test on macOS with Xcode. The project links LoopKit-family frameworks from `BUILT_PRODUCTS_DIR`, so a standalone checkout needs those products supplied by the surrounding LoopWorkspace/build environment.
- Resolve the three project-local Swift packages with `xcodebuild -resolvePackageDependencies -project Loop.xcodeproj`; pins live in `Loop.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Build without signing: `xcodebuild -project Loop.xcodeproj -target Loop -destination 'generic/platform=iOS Simulator' build CODE_SIGN_IDENTITY='' CODE_SIGNING_ALLOWED=NO`. Use the target because the shared `Loop` scheme still contains a removed `Cartfile` build entry.
- Run the current suite: `xcodebuild -project Loop.xcodeproj -scheme LoopTests -destination 'platform=iOS Simulator,name=<installed simulator>' test CODE_SIGN_IDENTITY='' CODE_SIGNING_ALLOWED=NO`.
- Run one class or method by appending `-only-testing:LoopTests/<TestClass>` or `-only-testing:LoopTests/<TestClass>/<testMethod>`. `LoopTests` is app-hosted and builds `Loop.app`; it is not a standalone library test bundle.
- Do not copy the Travis `Cartfile`, `Learn`, or `DoseMathTests` commands: those targets are absent from the current project. There is no configured lint or formatter task in this checkout; treat a warning-clean focused build/test as verification.

## Generated And Local Configuration

- `Loop.xcconfig` supplies bundle IDs, signing, feature compilation conditions, cache duration, and deployment settings. Put local overrides in ignored `LoopOverride.xcconfig` or the parent `LoopConfigOverride.xcconfig`; version overrides use `VersionOverride.xcconfig` locally or in the parent directory.
- The Loop and Watch build phases delete and recreate `DerivedAssets.xcassets` from `DerivedAssetsBase.xcassets`, then overlay `DerivedAssetsOverride.xcassets` or parent workspace override assets. Edit base/override catalogs, not generated contents; only each generated catalog's `Contents.json` is tracked.
- Workspace inputs are consumed during the Loop build: `${WORKSPACE_ROOT}/Scenarios`, `.loopplugin` products, parent override assets/config, and `../InfoCustomizations.txt`. Scenarios/plugins/overrides may be absent, but the Info customization script reads its parent file unconditionally.

## Testing Notes

- Test fixtures under `LoopTests/Fixtures` are Xcode resources; when adding or renaming one, update project target membership as well as filesystem contents.
- Simulator scenarios require the `SCENARIOS_ENABLED` compilation condition plus mock pump and CGM managers. See `Documentation/Testing/Scenarios.md`; `Scripts/make_scenario.py` emits a sample JSON scenario.
- Scenario dates are offsets in seconds relative to load time, not absolute timestamps. Advancing a scenario executes full loop iterations and can apply suggested basal behavior.
