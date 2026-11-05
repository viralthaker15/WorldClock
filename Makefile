# World Clock build helpers (think npm scripts). Run `make help`.

PROJECT  = WorldClock.xcodeproj
SCHEME   = WorldClock
DERIVED  = build/DerivedData
APP      = $(DERIVED)/Build/Products/Release/WorldClock.app
XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED)

.PHONY: help test build run install uninstall clean

help:
	@echo "make test       run the unit tests (Debug)"
	@echo "make build      build the Release app into $(APP)"
	@echo "make run        build and launch the Release app from the build folder"
	@echo "make install    build, copy to /Applications and launch"
	@echo "make uninstall  quit and remove /Applications/WorldClock.app"
	@echo "make clean      delete the build folder"

test:
	$(XCODEBUILD) -configuration Debug -destination 'platform=macOS' test

build:
	$(XCODEBUILD) -configuration Release -destination 'generic/platform=macOS' -quiet build
	@echo "Built $(APP)"

run: build
	-pkill -x WorldClock
	open "$(APP)"

install: build
	-pkill -x WorldClock
	rm -rf /Applications/WorldClock.app
	ditto "$(APP)" /Applications/WorldClock.app
	open /Applications/WorldClock.app
	@echo "Installed /Applications/WorldClock.app"

uninstall:
	-pkill -x WorldClock
	rm -rf /Applications/WorldClock.app

clean:
	rm -rf build
