#!/bin/sh
XCODE_BUILD_DIR="build"

xcodebuild -sdk iphoneos3.2 "ARCHS=armv6 armv7" clean build
xcodebuild -sdk iphonesimulator3.2 "ARCHS=i386 x86_64" "VALID_ARCHS=i386 x86_64" clean build
lipo -output release/libAFCache.a -create $XCODE_BUILD_DIR/Release-iphoneos/libAFCache.a $XCODE_BUILD_DIR/Release-iphonesimulator/libAFCache.a

cat AFCacheableItemInfo.h > release/AFCacheLib.h.tmp
cat AFCache.h >> release/AFCacheLib.h.tmp
cat AFCacheableItem.h >> release/AFCacheLib.h.tmp
cat AFURLCache.h >> release/AFCacheLib.h.tmp

cat release/AFCacheLib.h.tmp | sed -e s,\#import.*,,g > release/AFCacheLib.h
rm release/AFCacheLib.h.tmp
cp CHANGES release/
