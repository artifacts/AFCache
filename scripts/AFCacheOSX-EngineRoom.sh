#!/bin/bash

set -e
#set -x

OSX_SDK=macosx10.6
OSX_ARCHS="x86_64 i386 ppc"


ENGINEROOM_CFLAGS="-DDONT_USE_ENGINEROOM"
ENGINEROOM_LDFLAGS=""

ENGINEROOM_OSX="$SOURCE_ROOT/../EngineRoom/EngineRoom-OSX"

if [ -e "$ENGINEROOM_OSX" ] ; then
	ENGINEROOM_CFLAGS="-DUSE_ENGINEROOM -DER_EMBEDDED_NAME=AFCache"
	ENGINEROOM_LDFLAGS="-weak_framework EngineRoom"

	pushd "$ENGINEROOM_OSX"
	xcodebuild -target EngineRoom-OSX -sdk $OSX_SDK -configuration "$CONFIGURATION" \
		"BUILD_DIR=$BUILD_DIR" \
		"ARCHS=$OSX_ARCHS" \
		 clean build
	popd
fi

# DERIVED_SOURCES_DIR is too "clean"
XCCONFIG="$BUILD_DIR/AFCache.xcconfig"
cat <<__EOCONFIG__ > "$XCCONFIG"
ARCHS=$OSX_ARCHS
ENGINEROOM_CFLAGS=$ENGINEROOM_CFLAGS
ENGINEROOM_LDFLAGS=$ENGINEROOM_LDFLAGS
__EOCONFIG__

xcodebuild -target AFCacheOSX -sdk $OSX_SDK -configuration "$CONFIGURATION" -xcconfig "$XCCONFIG" clean build

exit 0
