#!/bin/sh
XCODE_BUILD_DIR="build"

set -e
set -x


xcodebuild -project AFCache-iOS.xcodeproj -target AFCache-iOS -sdk iphoneos4.3 "ARCHS=armv6 armv7" clean build
xcodebuild -project AFCache-iOS.xcodeproj -target AFCache-iOS -sdk iphonesimulator4.3 "ARCHS=i386 x86_64" "VALID_ARCHS=i386 x86_64" clean build
lipo -output release/libAFCache-iOS.a -create $XCODE_BUILD_DIR/Release-iphoneos/libAFCache-iOS.a $XCODE_BUILD_DIR/Release-iphonesimulator/libAFCache-iOS.a

cd scripts
./updateAPI.sh
cd ..
cp CHANGES release/
