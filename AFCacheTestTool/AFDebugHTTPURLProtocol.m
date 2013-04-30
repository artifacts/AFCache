//
//  AFDebugHTTPURLProtocol.m
//  AFCacheTestTool
//
//  Created by Michael Markowski on 12.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import "AFDebugHTTPURLProtocol.h"

@implementation AFDebugHTTPURLProtocol

+ (void)setDebugDelegate:(id<AFCacheableItemDelegate>)aDelegate {
    staticDebugDelegate = aDelegate;
}

- (void) connectionDidFail: (AFCacheableItem *) cacheableItem {
    [staticDebugDelegate connectionDidFail: cacheableItem];
    [super connectionDidFail:cacheableItem];
}

- (void) connectionDidFinish: (AFCacheableItem *) cacheableItem {
    [staticDebugDelegate connectionDidFinish: cacheableItem];
    [super connectionDidFinish:cacheableItem];
}

@end
