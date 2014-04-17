//
//  AFLookupStrategy.m
//  AFCache-iOS
//
//  Created by Michael Markowski on 17/04/14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFLookupStrategy.h"
#import "AFCache.h"

@implementation AFLookupStrategy

- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) URL {
    return [[AFCache sharedInstance] cacheableItemFromCacheStore:URL];
}

@end
