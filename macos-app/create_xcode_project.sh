#!/bin/bash

# Grimoire Xcode Project Creation Script
# Creates a properly configured Xcode project with Info.plist

set -e

echo "🛠️  Creating Grimoire Xcode project..."

# Check if Xcode is installed
if ! xcode-select -p &> /dev/null; then
    echo "❌ Xcode is not installed. Please install Xcode from the App Store."
    exit 1
fi

# Get Xcode version
XCODE_VERSION=$(xcodebuild -version | head -n 1 | awk '{print $2}')
echo "📱 Xcode version: $XCODE_VERSION"

# Create project directory structure
PROJECT_NAME="Grimoire"
PROJECT_DIR="${PROJECT_NAME}.xcodeproj"
CONTENTS_DIR="${PROJECT_DIR}/project.xcworkspace/contents.xcworkspacedata"
SCHEMES_DIR="${PROJECT_DIR}/xcshareddata/xcschemes"
SHARED_DATA_DIR="${PROJECT_DIR}/xcshareddata"
PBXPROJ_FILE="${PROJECT_DIR}/project.pbxproj"
RESOURCES_DIR="Resources"

echo "📁 Creating project structure..."

# Create directories
mkdir -p "$SCHEMES_DIR"
mkdir -p "$SHARED_DATA_DIR"
mkdir -p "$RESOURCES_DIR"

# Create Info.plist
cat > "${RESOURCES_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2024 Grimoire. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSMainStoryboardFile</key>
	<string>Main</string>
</dict>
</plist>
EOF

echo "✅ Created Info.plist"

# Create scheme file
cat > "${SCHEMES_DIR}/${PROJECT_NAME}.xcscheme" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "GRIM_MAIN"
               BuildableName = "Grimoire.app"
               BlueprintName = "Grimoire"
               ReferencedContainer = "container:Grimoire.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "GRIM_MAIN"
               BuildableName = "Grimoire.app"
               BlueprintName = "Grimoire"
               ReferencedContainer = "container:Grimoire.xcodeproj">
            </BuildableReference>
         </BuildableProductRunnable>
         <AdditionalOptions>
         </AdditionalOptions>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "GRIM_MAIN"
               BuildableName = "Grimoire.app"
               BlueprintName = "Grimoire"
               ReferencedContainer = "container:Grimoire.xcodeproj">
            </BuildableReference>
         </BuildableProductRunnable>
      </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
EOF

echo "✅ Created scheme file"

# Create workspace settings
cat > "${SHARED_DATA_DIR}/WorkspaceSettings.xcsettings" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>BuildSystemType</key>
    <string>Original</string>
    <key>PreviewsEnabled</key>
    <false/>
    <key>IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded</key>
    <false/>
</dict>
</plist>
EOF

# Create IDETemplateMacros.plist
cat > "${SHARED_DATA_DIR}/IDETemplateMacros.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

# Create project.pbxproj file
cat > "$PBXPROJ_FILE" << 'EOF'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 55;
	objects = {

/* Begin PBXBuildFile section */
		GRIM_APP_BUILD /* GrimoireApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_APP /* GrimoireApp.swift */; };
		GRIM_CONTENT_BUILD /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_CONTENT /* ContentView.swift */; };
		GRIM_SIDEBAR_BUILD /* SidebarView.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_SIDEBAR /* SidebarView.swift */; };
		GRIM_EDITOR_BUILD /* EditorView.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_EDITOR /* EditorView.swift */; };
		GRIM_BACKLINKS_BUILD /* BacklinksView.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_BACKLINKS /* BacklinksView.swift */; };
		GRIM_SETTINGS_BUILD /* SettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_SETTINGS /* SettingsView.swift */; };
		GRIM_DEBUG_BUILD /* DebugTools.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_DEBUG /* DebugTools.swift */; };
		GRIM_DOMAIN_MODELS_BUILD /* Models.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_DOMAIN_MODELS /* Models.swift */; };
		GRIM_DATA_NOTE_REPO_BUILD /* NoteRepository.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_DATA_NOTE_REPO /* NoteRepository.swift */; };
		GRIM_DATA_SEARCH_REPO_BUILD /* SearchRepository.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_DATA_SEARCH_REPO /* SearchRepository.swift */; };
		GRIM_STORE_NOTE_BUILD /* NoteStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_STORE_NOTE /* NoteStore.swift */; };
		GRIM_STORE_BACKLINK_BUILD /* BacklinksStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = GRIM_STORE_BACKLINK /* BacklinksStore.swift */; };
		GRIM_INFOPLIST_BUILD /* Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = GRIM_INFOPLIST /* Info.plist */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		GRIM_APP /* GrimoireApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GrimoireApp.swift; sourceTree = "<group>"; };
		GRIM_CONTENT /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
		GRIM_SIDEBAR /* SidebarView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SidebarView.swift; sourceTree = "<group>"; };
		GRIM_EDITOR /* EditorView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EditorView.swift; sourceTree = "<group>"; };
		GRIM_BACKLINKS /* BacklinksView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BacklinksView.swift; sourceTree = "<group>"; };
		GRIM_SETTINGS /* SettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
		GRIM_DEBUG /* DebugTools.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DebugTools.swift; sourceTree = "<group>"; };
		GRIM_DOMAIN_MODELS /* Models.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Models.swift; sourceTree = "<group>"; };
		GRIM_DATA_NOTE_REPO /* NoteRepository.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NoteRepository.swift; sourceTree = "<group>"; };
		GRIM_DATA_SEARCH_REPO /* SearchRepository.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SearchRepository.swift; sourceTree = "<group>"; };
		GRIM_STORE_NOTE /* NoteStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NoteStore.swift; sourceTree = "<group>"; };
		GRIM_STORE_BACKLINK /* BacklinksStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BacklinksStore.swift; sourceTree = "<group>"; };
		GRIM_INFOPLIST /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		GRIM_PRODUCT /* Grimoire.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Grimoire.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		GRIM_FRAMEWORKS /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		GRIM_GROUP_ROOT = {
			isa = PBXGroup;
			children = (
				GRIM_GROUP_SOURCES,
				GRIM_GROUP_RESOURCES,
				GRIM_GROUP_PRODUCTS,
			);
			sourceTree = "<group>";
		};
		GRIM_GROUP_SOURCES = {
			isa = PBXGroup;
			children = (
				GRIM_APP,
				GRIM_VIEWS_GROUP,
				GRIM_GROUP_DOMAIN,
				GRIM_GROUP_DATA,
				GRIM_GROUP_STORES,
				GRIM_DEBUG,
			);
			name = Sources;
			sourceTree = "<group>";
		};
		GRIM_VIEWS_GROUP = {
			isa = PBXGroup;
			children = (
				GRIM_CONTENT,
				GRIM_SIDEBAR,
				GRIM_EDITOR,
				GRIM_BACKLINKS,
				GRIM_SETTINGS,
			);
			name = Views;
			path = "";
			sourceTree = "<group>";
		};
		GRIM_GROUP_DOMAIN = {
			isa = PBXGroup;
			children = (
				GRIM_DOMAIN_MODELS,
			);
			name = Domain;
			path = Domain;
			sourceTree = "<group>";
		};
		GRIM_GROUP_DATA = {
			isa = PBXGroup;
			children = (
				GRIM_DATA_NOTE_REPO,
				GRIM_DATA_SEARCH_REPO,
			);
			name = Data;
			path = Data;
			sourceTree = "<group>";
		};
		GRIM_GROUP_STORES = {
			isa = PBXGroup;
			children = (
				GRIM_STORE_NOTE,
				GRIM_STORE_BACKLINK,
			);
			name = Stores;
			path = Stores;
			sourceTree = "<group>";
		};
		GRIM_GROUP_RESOURCES = {
			isa = PBXGroup;
			children = (
				GRIM_INFOPLIST,
			);
			name = Resources;
			path = Resources;
			sourceTree = "<group>";
		};
		GRIM_GROUP_PRODUCTS = {
			isa = PBXGroup;
			children = (
				GRIM_PRODUCT,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		GRIM_TARGET_MAIN /* Grimoire */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = GRIM_CONFIG_LIST_TARGET /* Build configuration list for PBXNativeTarget "Grimoire" */;
			buildPhases = (
				GRIM_SOURCES_PHASE /* Sources */,
				GRIM_FRAMEWORKS /* Frameworks */,
				GRIM_RESOURCES_PHASE /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Grimoire;
			productName = Grimoire;
			productReference = GRIM_PRODUCT /* Grimoire.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		GRIM_PROJECT /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					GRIM_TARGET_MAIN = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = GRIM_CONFIG_LIST_PROJECT /* Build configuration list for PBXProject "Grimoire" */;
			compatibilityVersion = "Xcode 15.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = GRIM_GROUP_ROOT;
			productRefGroup = GRIM_GROUP_PRODUCTS /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				GRIM_TARGET_MAIN /* Grimoire */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		GRIM_RESOURCES_PHASE /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				GRIM_INFOPLIST_BUILD /* Info.plist in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		GRIM_SOURCES_PHASE /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				GRIM_APP_BUILD /* GrimoireApp.swift in Sources */,
				GRIM_CONTENT_BUILD /* ContentView.swift in Sources */,
				GRIM_SIDEBAR_BUILD /* SidebarView.swift in Sources */,
				GRIM_EDITOR_BUILD /* EditorView.swift in Sources */,
				GRIM_BACKLINKS_BUILD /* BacklinksView.swift in Sources */,
				GRIM_SETTINGS_BUILD /* SettingsView.swift in Sources */,
				GRIM_DEBUG_BUILD /* DebugTools.swift in Sources */,
				GRIM_DOMAIN_MODELS_BUILD /* Models.swift in Sources */,
				GRIM_DATA_NOTE_REPO_BUILD /* NoteRepository.swift in Sources */,
				GRIM_DATA_SEARCH_REPO_BUILD /* SearchRepository.swift in Sources */,
				GRIM_STORE_NOTE_BUILD /* NoteStore.swift in Sources */,
				GRIM_STORE_BACKLINK_BUILD /* BacklinksStore.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		GRIM_CONFIG_DEBUG /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				INFOPLIST_FILE = Resources/Info.plist;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.grimoire.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		GRIM_CONFIG_RELEASE /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu11;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				INFOPLIST_FILE = Resources/Info.plist;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.grimoire.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		GRIM_CONFIG_LIST_PROJECT /* Build configuration list for PBXProject "Grimoire" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				GRIM_CONFIG_DEBUG /* Debug */,
				GRIM_CONFIG_RELEASE /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		GRIM_CONFIG_LIST_TARGET /* Build configuration list for PBXNativeTarget "Grimoire" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				GRIM_CONFIG_DEBUG /* Debug */,
				GRIM_CONFIG_RELEASE /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

	};
	rootObject = GRIM_PROJECT /* Project object */;
}
EOF

echo "✅ Created project.pbxproj"

# Create workspace contents
mkdir -p "${PROJECT_DIR}/project.xcworkspace"
cat > "${CONTENTS_DIR}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
EOF

echo "✅ Created workspace"

# Create a simple build script
cat > "build_app.sh" << 'EOF'
#!/bin/bash

# Grimoire Build Script
# Builds the macOS app from command line

set -e

echo "🔨 Building Grimoire..."

# Clean up old builds
rm -rf "Build"
rm -rf "Grimoire.app"

# Build the project
xcodebuild \
    -project "Grimoire.xcodeproj" \
    -scheme "Grimoire" \
    -configuration "Debug" \
    -derivedDataPath "Build" \
    -destination "platform=macOS" \
    build

# Check if build succeeded
if [ $? -eq 0 ]; then
    # Copy the built app
    if [ -d "Build/Build/Products/Debug/Grimoire.app" ]; then
        cp -R "Build/Build/Products/Debug/Grimoire.app" .
        echo "✅ Build successful! Grimoire.app created."
        echo "🚀 To run: open Grimoire.app"
    else
        echo "❌ Build succeeded but app not found at expected location"
        echo "📁 Check: Build/Build/Products/Debug/"
    fi
else
    echo "❌ Build failed"
    exit 1
fi
EOF

chmod +x build_app.sh

echo "✅ Created build script"

# Create README for Xcode project
cat > "XCODE_SETUP.md" << 'EOF'
# Xcode Project Setup

## Quick Start

1. **Open the project**:
   ```bash
   open Grimoire.xcodeproj
   ```

2. **Build and run**:
   - Select the "Grimoire" scheme
   - Choose "My Mac" as the destination
   - Press `Cmd + R` to build and run

## Alternative: Command Line Build

```bash
# Build from command line
./build_app.sh

# Run the built app
open Grimoire.app
```

## Project Structure

```
macos-app/
├── Grimoire.xcodeproj/          # Xcode project
├── Resources/                   # Resources (Info.plist)
├── Views/                       # SwiftUI views
├── FileManager/                 # Note management
├── Networking/                  # API communication
├── GrimoireApp.swift           # App entry point
├── build_app.sh                # Build script
└── XCODE_SETUP.md              # This file
```

## Troubleshooting

### "Cannot code sign" error
The project is configured with:
- `PRODUCT_BUNDLE_IDENTIFIER = com.grimoire.app`
- `INFOPLIST_FILE = Resources/Info.plist`
- No code signing required for development

### Missing files
If files are missing from the project:
1. Open Grimoire.xcodeproj
2. Drag missing files into the project navigator
3. Make sure "Copy items if needed" is checked
4. Add to the Grimoire target

### Swift Package Dependencies
If you want Markdown preview:
1. In Xcode: File → Add Packages...
2. Enter: `https://github.com/gonzalezreal/swift-markdown-ui`
3. Add to Grimoire target

## Backend Requirements

Make sure the Python backend is running:
```bash
cd ../backend
source venv/bin/activate
python3 main.py
```

Or use the launcher:
```bash
cd ..
./grimoire backend
```

The app will connect to: http://127.0.0.1:8000
EOF

echo "✅ Created Xcode setup documentation"

echo ""
echo "🎉 Xcode project created successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Open the project:"
echo "   open Grimoire.xcodeproj"
echo ""
echo "2. Or build from command line:"
echo "   ./build_app.sh"
echo ""
echo "3. Add Swift files to the project (if not already added):"
echo "   - Drag files/folders into Xcode project navigator"
echo "   - Check 'Copy items if needed'"
echo "   - Add to the Grimoire target"
echo ""
echo "📚 For detailed setup, see: XCODE_SETUP.md"
