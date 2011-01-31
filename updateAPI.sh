#!/bin/sh

cat AFCacheableItemInfo.h > release/AFCacheLib.h.tmp
cat AFCache.h >> release/AFCacheLib.h.tmp
cat AFCacheableItem.h >> release/AFCacheLib.h.tmp
cat AFURLCache.h >> release/AFCacheLib.h.tmp
cat AFCacheableItem+Packaging.h >> release/AFCacheLib.h.tmp
cat AFPackageInfo.h >> release/AFCacheLib.h.tmp
cat AFCache+Packaging.h >> release/AFCacheLib.h.tmp

cat release/AFCacheLib.h.tmp | sed -e s,\#import.*,,g > release/AFCacheLib.h
rm release/AFCacheLib.h.tmp


