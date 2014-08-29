//
//  AFCache+DeprecatedAPI.m
//  AFCache
//
//  Created by Lars Blumberg on 29.08.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCache+DeprecatedAPI.h"

@implementation AFCache (DeprecatedAPI)

- (AFCacheableItem *)cachedObjectForURLSynchroneous: (NSURL *) url {
    return [self cachedObjectForURLSynchronous:url];
}

- (AFCacheableItem *)cachedObjectForURLSynchroneous:(NSURL *)url options: (int)options {
    return [self cachedObjectForURLSynchronous:url options:options];
}

@end
