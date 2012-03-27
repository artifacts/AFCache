#!/bin/sh

HEADER_DIR=../src/shared

cat $HEADER_DIR/AFCacheableItemInfo.h > ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFCache.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFCacheableItem.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFURLCache.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFCacheableItem+Packaging.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFPackageInfo.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFCache+Packaging.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFCachePackageCreator.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFHTTPURLProtocol.h >> ../release/AFCacheLib.h.tmp
cat $HEADER_DIR/AFMediaTypeParser.h >> ../release/AFCacheLib.h.tmp

cat ../release/AFCacheLib.h.tmp | sed -e s,\#import.*,,g > ../release/AFCacheLib.h
rm ../release/AFCacheLib.h.tmp


