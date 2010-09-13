//
//  AFCache+Packaging.h
//  AFCache
//
//  Created by Michael Markowski on 13.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFCache.h"

@interface AFCache (Packaging)



- (BOOL)importCacheableItem:(AFCacheableItem*)cacheableItem withData:(NSData*)theData;
- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate;
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem;
- (void)packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem;
- (void)purgeCacheableItemForURL:(NSURL*)url;
- (void)cancelUnzipping;

@end
