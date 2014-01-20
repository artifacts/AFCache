#!/bin/sh
XCODE_BUILD_DIR="../build"

set -e
set -x


xcodebuild -project ../AFCache-iOS.xcodeproj -target AFCache-iOS -sdk iphoneos "ARCHS=armv6 armv7" clean build
xcodebuild -project ../AFCache-iOS.xcodeproj -target AFCache-iOS -sdk iphonesimulator "ARCHS=i386 x86_64" "VALID_ARCHS=i386 x86_64" clean build
lipo -output ../release/libAFCache-iOS.a -create $XCODE_BUILD_DIR/Release-iphoneos/libAFCache-iOS.a $XCODE_BUILD_DIR/Release-iphonesimulator/libAFCache-iOS.a

./updateAPI.sh
cp ../CHANGES ../release/
