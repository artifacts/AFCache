//
//  AFCache+Packaging.h
//  AFCache
//
//  Created by Michael Markowski on 13.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFCache.h"
#import "AFPackageInfo.h"

@interface AFCache (Packaging)



- (BOOL)importCacheableItem:(AFCacheableItem*)cacheableItem withData:(NSData*)theData;
- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate;
- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate username: (NSString*) username password: (NSString*) password;
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem preservePackageInfo:(BOOL)preservePackageInfo;
- (void)packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem;
- (NSString*)userDataPathForPackageArchiveKey:(NSString*)archiveKey;
- (AFPackageInfo*)packageInfoForURL:(NSURL*)url;

// wipe out a cachable item completely
- (void)purgeCacheableItemForURL:(NSURL*)url;

// remove an imported package zip
- (void)purgePackageArchiveForURL:(NSURL*)url;

// announce files residing in the urlcachestore folder by reading the cache manifest file
// this method assumes that the files already have been extracted into the urlcachestore folder
- (AFPackageInfo*)newPackageInfoByImportingCacheManifestAtPath:(NSString*)manifestPath intoCacheStoreWithPath:(NSString*)urlCacheStorePath withPackageURL:(NSURL*)packageURL;
- (void)storeCacheInfo:(NSDictionary*)dictionary;

// Deprecated methods:

#pragma mark -
#pragma mark Deprecated methods

// Deprecated. Use consumePackageArchive:preservePackageInfo: instead
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem DEPRECATED_ATTRIBUTE; 
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem preservePackageInfo:(BOOL)preservePackageInfo;
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem userData:(NSDictionary*)userData preservePackageInfo:(BOOL)preservePackageInfo;

@end
