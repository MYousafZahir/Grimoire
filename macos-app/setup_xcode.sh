#!/bin/bash

# Grimoire Xcode Setup Script
# Properly sets up Xcode project with all Swift files

set -e

echo "🛠️  Setting up Grimoire Xcode project..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if Xcode is installed
if ! xcode-select -p &> /dev/null; then
    echo -e "${RED}❌ Xcode is not installed. Please install Xcode from the App Store.${NC}"
    exit 1
fi

# Get Xcode version
XCODE_VERSION=$(xcodebuild -version | head -n 1 | awk '{print $2}')
echo -e "${BLUE}📱 Xcode version: $XCODE_VERSION${NC}"

# Create project directory structure
echo -e "${BLUE}📁 Creating project structure...${NC}"

# Remove old project if exists
rm -rf "Grimoire.xcodeproj" "Grimoire.app" "Build" 2>/dev/null || true

# Create directories
mkdir -p "Grimoire.xcodeproj/project.xcworkspace"
mkdir -p "Grimoire.xcodeproj/xcshareddata/xcschemes"
mkdir -p "Resources"

# Create Info.plist
echo -e "${BLUE}📄 Creating Info.plist...${NC}"
cat > "Resources/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>com.grimoire.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Grimoire</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2024 Grimoire. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# Create scheme file
echo -e "${BLUE}📋 Creating scheme...${NC}"
cat > "Grimoire.xcodeproj/xcshareddata/xcschemes/Grimoire.xcscheme" << 'EOF'
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

# Create workspace
echo -e "${BLUE}🏢 Creating workspace...${NC}"
cat > "Grimoire.xcodeproj/project.xcworkspace/contents.xcworkspacedata" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
EOF

# Create project.pbxproj
echo -e "${BLUE}🏗️  Creating project.pbxproj...${NC}"

# First, let's create a simple project using xcodegen if available, otherwise create manually
if command -v xcodegen &> /dev/null; then
    echo -e "${BLUE}📦 Using xcodegen to create project...${NC}"
    cat > "project.yml" << 'EOF'
name: Grimoire
options:
  bundleIdPrefix: com.grimoire
  deploymentTarget:
    macOS: "13.0"
targets:
  Grimoire:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - path: .
        excludes:
          - "Grimoire.xcodeproj"
          - "Build"
          - "*.yml"
          - "*.sh"
          - "README.md"
          - "XCODE_SETUP.md"
    settings:
      INFOPLIST_FILE: Resources/Info.plist
      PRODUCT_BUNDLE_IDENTIFIER: com.grimoire.app
      CODE_SIGN_IDENTITY: ""
      CODE_SIGNING_REQUIRED: NO
      CODE_SIGNING_ALLOWED: NO
    preBuildScripts:
      - name: Check Backend
        script: |
          echo "Checking if backend is running..."
          if ! curl -s http://127.0.0.1:8000 > /dev/null; then
            echo "⚠️  Backend not running. Start it with: ../grimoire backend"
          else
            echo "✅ Backend is running"
          fi
EOF
    xcodegen generate
    rm -f project.yml
else
    echo -e "${YELLOW}⚠ xcodegen not found, creating simple project...${NC}"
    # Create a simple project file
    cat > "Grimoire.xcodeproj/project.pbxproj" << 'EOF'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		GRIM_APP_BUILD = {isa = PBXBuildFile; fileRef = GRIM_APP; };
		GRIM_CONTENT_BUILD = {isa = PBXBuildFile; fileRef = GRIM_CONTENT; };
		GRIM_SIDEBAR_BUILD = {isa = PBXBuildFile; fileRef = GRIM_SIDEBAR; };
		GRIM_EDITOR_BUILD = {isa = PBXBuildFile; fileRef = GRIM_EDITOR; };
		GRIM_BACKLINKS_BUILD = {isa = PBXBuildFile; fileRef = GRIM_BACKLINKS; };
		GRIM_SETTINGS_BUILD = {isa = PBXBuildFile; fileRef = GRIM_SETTINGS; };
		GRIM_NOTEMGR_BUILD = {isa = PBXBuildFile; fileRef = GRIM_NOTEMGR; };
		GRIM_SEARCHMGR_BUILD = {isa = PBXBuildFile; fileRef = GRIM_SEARCHMGR; };
		GRIM_INFOPLIST_BUILD = {isa = PBXBuildFile; fileRef = GRIM_INFOPLIST; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		GRIM_APP = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GrimoireApp.swift; sourceTree = "<group>"; };
		GRIM_CONTENT = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
		GRIM_SIDEBAR = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SidebarView.swift; sourceTree = "<group>"; };
		GRIM_EDITOR = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = EditorView.swift; sourceTree = "<group>"; };
		GRIM_BACKLINKS = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BacklinksView.swift; sourceTree = "<group>"; };
		GRIM_SETTINGS = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SettingsView.swift; sourceTree = "<group>"; };
		GRIM_NOTEMGR = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NoteManager.swift; sourceTree = "<group>"; };
		GRIM_SEARCHMGR = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SearchManager.swift; sourceTree = "<group>"; };
		GRIM_INFOPLIST = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		GRIM_PRODUCT = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Grimoire.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		GRIM_FRAMEWORKS = {
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
				GRIM_CONTENT,
				GRIM_SIDEBAR,
				GRIM_EDITOR,
				GRIM_BACKLINKS,
				GRIM_SETTINGS,
				GRIM_NOTEMGR,
				GRIM_SEARCHMGR,
			);
			name = Sources;
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
		GRIM_TARGET = {
			isa = PBXNativeTarget;
			buildConfigurationList = GRIM_CONFIG_LIST_TARGET;
			buildPhases = (
				GRIM_SOURCES,
				GRIM_FRAMEWORKS,
				GRIM_RESOURCES,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Grimoire;
			productName = Grimoire;
			productReference = GRIM_PRODUCT;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		GRIM_PROJECT = {
			isa = PBXProject;
			attributes = {
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					GRIM_TARGET = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = GRIM_CONFIG_LIST_PROJECT;
			compatibilityVersion = "Xcode 15.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = GRIM_GROUP_ROOT;
			productRefGroup = GRIM_GROUP_PRODUCTS;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				GRIM_TARGET,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		GRIM_RESOURCES = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				GRIM_INFOPLIST_BUILD,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		GRIM_SOURCES = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				GRIM_APP_BUILD,
				GRIM_CONTENT_BUILD,
				GRIM_SIDEBAR_BUILD,
				GRIM_EDITOR_BUILD,
				GRIM_BACKLINKS_BUILD,
				GRIM_SETTINGS_BUILD,
				GRIM_NOTEMGR_BUILD,
				GRIM_SEARCHMGR_BUILD,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		GRIM_CONFIG_DEBUG = {
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
		GRIM_CONFIG_RELEASE = {
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
				GCC_WARN_64_TO_32_BIT_CONVISION = YES;
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
		GRIM_CONFIG_LIST_PROJECT = {
			isa = XCConfigurationList;
			buildConfigurations = (
				GRIM_CONFIG_DEBUG,
				GRIM_CONFIG_RELEASE,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		GRIM_CONFIG_LIST_TARGET = {
			isa = XCConfigurationList;
			buildConfigurations = (
				GRIM_CONFIG_DEBUG,
				GRIM_CONFIG_RELEASE,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

	};
	rootObject = GRIM_PROJECT;
}
EOF
fi

# Create simple build script
echo -e "${BLUE}📦 Creating build script...${NC}"
cat > "build_simple.sh" << 'EOF'
#!/bin/bash

# Simple build script for Grimoire

set -e

echo "Building Grimoire..."

# Clean
rm -rf Build Grimoire.app 2>/dev/null || true

# Build
xcodebuild \
    -project Grimoire.xcodeproj \
    -scheme Grimoire \
    -configuration Debug \
    -derivedDataPath Build \
    -destination "platform=macOS" \
    -quiet \
    build

# Check result
if [ $? -eq 0 ]; then
    # Find the built app
    if [ -d "Build/Build/Products/Debug/Grimoire.app" ]; then
        cp -R "Build/Build/Products/Debug/Grimoire.app" .
        echo "✅ Build successful! Grimoire.app created."
        echo "🚀 Run: open Grimoire.app"
    else
        echo "❌ Build succeeded but app not found"
        exit 1
    fi
else
    echo "❌ Build failed"
    exit 1
fi
EOF

chmod +x build_simple.sh

# Create instructions
echo -e "${BLUE}📝 Creating instructions...${NC}"
cat > "XCODE_GUIDE.md" << 'EOF'
# Xcode Setup Guide

## Quick Start

### Option 1: Build from command line
```bash
# Build the app
./build_simple.sh

# Run the app (make sure backend is running first)
open Grimoire.app
```

### Option 2: Open in Xcode
```bash
# Open the project
open Grimoire.xcodeproj
```
Then:
1. Select "Grimoire" scheme
2. Choose "My Mac" as destination
3. Press `Cmd + R` to build and run

## Project Structure

The Xcode project includes:
- `GrimoireApp.swift` - App entry point
- `ContentView.swift` - Main layout
- `SidebarView.swift` - Note hierarchy
- `EditorView.swift` - Markdown editor
- `BacklinksView.swift` - Semantic connections
- `SettingsView.swift` - App settings
- `NoteManager.swift` - Note management
- `SearchManager.swift` - Semantic search
- `Resources/Info.plist` - App configuration

## Backend Requirements

The app needs the Python backend running:
```bash
# From the Grimoire root directory
./grimoire backend
```

Or manually:
```bash
cd ../backend
source venv/bin/activate
python3 main.py
```

The app connects to: http://127.0.0.1:8000

## Troubleshooting

### "Cannot code sign" error
The project is configured with:
- No code signing required for development
- `PRODUCT_BUNDLE_IDENTIFIER = com.grimoire.app`
- `CODE_SIGNING_ALLOWED = NO`

### Missing files
If files are missing:
1. Open `Grimoire.xcodeproj`
2. Drag missing files into project navigator
3. Check "Copy items if needed"
4. Add to Grimoire target

### Build fails
Try:
1. Clean build folder: `rm -rf Build`
2. Open in Xcode and build manually
3. Check for Swift syntax errors
EOF

echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Xcode project setup complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"

echo -e "${BLUE}📋 Next steps:${NC}"
echo -e "  1. ${YELLOW}Build the app:${NC} ./build_simple.sh"
echo -e "  2. ${YELLOW}Or open in Xcode:${NC} open Grimoire.xcodeproj"
echo -e "  3. ${YELLOW}Make sure backend is running:${NC} ../grimoire backend"
echo -e ""
echo -e "${BLUE}📚 For detailed instructions:${NC} cat XCODE_GUIDE.md"
echo -e ""
