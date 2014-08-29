//
//  AFCache+DeprecatedAPI.h
//  AFCache
//
//  Created by Lars Blumberg on 29.08.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import <AFCache/AFCache.h>
#import <AvailabilityMacros.h>

@interface AFCache (DeprecatedAPI)

- (AFCacheableItem *)cachedObjectForURLSynchroneous: (NSURL *) url DEPRECATED_MSG_ATTRIBUTE("Use cachedObjectForURLSynchronous:");
- (AFCacheableItem *)cachedObjectForURLSynchroneous:(NSURL *)url options: (int)options DEPRECATED_MSG_ATTRIBUTE("Use cachedObjectForURLSynchronous:options:");

@end
