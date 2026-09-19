DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
SIM ?= iPhone 17
PROJECT = HabitFlow.xcodeproj
SCHEME = HabitFlow
DEST = platform=iOS Simulator,name=$(SIM)
CORE = Packages/HabitCore

# Toolchain paths so `swift test` works even before `xcode-select` points at Xcode.
TC = $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin
MAC_SDK = $(DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
MAC_FW = $(DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/Library/Frameworks
MAC_LIB = $(DEVELOPER_DIR)/Platforms/MacOSX.platform/Developer/usr/lib
CORE_FLAGS = -Xswiftc -F$(MAC_FW) -Xswiftc -I$(MAC_LIB) -Xlinker -F$(MAC_FW) -Xlinker -L$(MAC_LIB) -Xlinker -rpath -Xlinker $(MAC_FW) -Xlinker -rpath -Xlinker $(MAC_LIB)

.PHONY: gen build test test-core run device devices clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath build/DerivedData build | tail -40

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath build/DerivedData test | tail -60

test-core:
	cd $(CORE) && SDKROOT=$(MAC_SDK) $(TC)/swift test $(CORE_FLAGS)

run: build
	xcrun simctl boot "$(SIM)" 2>/dev/null || true
	xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/HabitFlow.app
	xcrun simctl launch booted com.muslimahaev.habitflow

# A free signing team hands out seven-day profiles, so the app has to be re-signed and
# reinstalled about weekly. One command beats a trip through Xcode every time.
# Pass DEVICE=<name or udid> when more than one iPhone is attached.
device: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
		-allowProvisioningUpdates build | tail -20
	xcrun devicectl device install app \
		$(if $(DEVICE),--device "$(DEVICE)",) \
		build/DerivedData/Build/Products/Release-iphoneos/HabitFlow.app

devices:
	xcrun devicectl list devices

clean:
	rm -rf build $(CORE)/.build
