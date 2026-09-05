# SoundPuddle CI build errors

- SHA: `73cd9f31d3ac5450d62c2fb6238e96a314b90e63`
- Run: 33979880177
- Xcode: Xcode 16.4

## Matching lines
```
59:/Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/Localizable.xcstrings:1:1: error: The data couldn’t be read because it isn’t in the correct format. (in target 'SoundPuddle' from project 'SoundPuddle')
66:** BUILD FAILED **
```

## Tail
```
Command line invocation:
    /Applications/Xcode_16.4.app/Contents/Developer/usr/bin/xcodebuild -project SoundPuddle.xcodeproj -scheme SoundPuddle -configuration Release -sdk iphoneos -destination generic/platform=iOS -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= CODE_SIGN_ENTITLEMENTS= DEVELOPMENT_TEAM= CURRENT_PROJECT_VERSION=88 clean build

Build settings from command line:
    CODE_SIGN_ENTITLEMENTS = 
    CODE_SIGN_IDENTITY = 
    CODE_SIGNING_ALLOWED = NO
    CODE_SIGNING_REQUIRED = NO
    CURRENT_PROJECT_VERSION = 88
    DEVELOPMENT_TEAM = 
    SDKROOT = iphoneos18.5

note: Using codesigning identity override: 
ComputePackagePrebuildTargetDependencyGraph

CreateBuildRequest

SendProjectDescription

CreateBuildOperation

** CLEAN SUCCEEDED **

note: Using codesigning identity override: 
ComputePackagePrebuildTargetDependencyGraph

Prepare packages

CreateBuildRequest

SendProjectDescription

CreateBuildOperation

ComputeTargetDependencyGraph
note: Building targets in dependency order
note: Target dependency graph (1 target)
    Target 'SoundPuddle' in project 'SoundPuddle' (no dependencies)

GatherProvisioningInputs

CreateBuildDescription

ExecuteExternalTool /Applications/Xcode_16.4.app/Contents/Developer/usr/bin/actool --print-asset-tag-combinations --output-format xml1 /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/Assets.xcassets

ExecuteExternalTool /Applications/Xcode_16.4.app/Contents/Developer/usr/bin/xcstringstool compile --dry-run --output-directory /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Intermediates.noindex/SoundPuddle.build/Release-iphoneos/SoundPuddle.build /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/Localizable.xcstrings

ExecuteExternalTool /Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -isysroot /Applications/Xcode_16.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.5.sdk -x c -c /dev/null

ExecuteExternalTool /Applications/Xcode_16.4.app/Contents/Developer/usr/bin/actool --version --output-format xml1

ExecuteExternalTool /Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc --version

ExecuteExternalTool /Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld -version_details

Build description signature: ff1e449e2b6c4c2488400040ecbcd143
Build description path: /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Intermediates.noindex/XCBuildData/ff1e449e2b6c4c2488400040ecbcd143.xcbuilddata
note: Disabling previews because SWIFT_VERSION is set and SWIFT_OPTIMIZATION_LEVEL=-O, expected -Onone (in target 'SoundPuddle' from project 'SoundPuddle')
/Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/Localizable.xcstrings:1:1: error: The data couldn’t be read because it isn’t in the correct format. (in target 'SoundPuddle' from project 'SoundPuddle')
warning: duplicate output file '/Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/00.b64' on task: CpResource /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/00.b64 /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/.assemble/00.b64 (in target 'SoundPuddle' from project 'SoundPuddle')
warning: duplicate output file '/Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/01.b64' on task: CpResource /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/01.b64 /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/.assemble/01.b64 (in target 'SoundPuddle' from project 'SoundPuddle')
warning: duplicate output file '/Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/02.b64' on task: CpResource /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/02.b64 /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/.assemble/02.b64 (in target 'SoundPuddle' from project 'SoundPuddle')
warning: duplicate output file '/Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/03.b64' on task: CpResource /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/03.b64 /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/.assemble/03.b64 (in target 'SoundPuddle' from project 'SoundPuddle')
warning: duplicate output file '/Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/04.b64' on task: CpResource /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/04.b64 /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/.assemble/04.b64 (in target 'SoundPuddle' from project 'SoundPuddle')
warning: duplicate output file '/Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/05.b64' on task: CpResource /Users/runner/work/SoundPuddle/SoundPuddle/build/Build/Products/Release-iphoneos/SoundPuddle.app/05.b64 /Users/runner/work/SoundPuddle/SoundPuddle/SoundPuddle/Resources/.assemble/05.b64 (in target 'SoundPuddle' from project 'SoundPuddle')
** BUILD FAILED **


The following build commands failed:
	Building project SoundPuddle with scheme SoundPuddle and configuration Release
(1 failure)
```
