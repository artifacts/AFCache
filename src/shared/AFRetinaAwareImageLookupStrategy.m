//
//  AFRetinaAwareImageLookupStrategy.m
//  AFCache-iOS
//
//  Created by Michael Markowski on 17/04/14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFRetinaAwareImageLookupStrategy.h"
#import "AFCache.h"
#import "AFCacheableItem.h"

@implementation AFRetinaAwareImageLookupStrategy

- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) URL {
    AFCacheableItem *imgItem = nil;
    /*
        url umbauen auf @2x wenn nicht schon drin
        imgItem = [[AFCache sharedInstance] cacheableItemFromCacheStore:URL];
        if not nil return
        sonst normaler lookup
     */
    return [[AFCache sharedInstance] cacheableItemFromCacheStore:URL];
}

@end
