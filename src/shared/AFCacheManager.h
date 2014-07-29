//
//  AFCacheManager.h
//  AFCache
//
//  Created by Sebastian Grimme on 29.07.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCache.h"

extern NSString *kAFCacheDefaultName;

@interface AFCacheManager : NSObject

/**
 * @return default cache instance
 */
+ (AFCache*)defaultCache;

/**
 * @return named cache instance
 */
+ (AFCache*)cacheForName:(NSString*)name;

@end
