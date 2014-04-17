//
//  AFLookupStrategy.h
//  AFCache-iOS
//
//  Created by Michael Markowski on 17/04/14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFCacheableItem.h"

@interface AFLookupStrategy : NSObject

- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) URL;

@end
