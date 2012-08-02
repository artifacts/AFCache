//
//  AFDebugHTTPURLProtocol.h
//  AFCacheTestTool
//
//  Created by Michael Markowski on 12.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import "AFHTTPURLProtocol.h"
#import "AFCache.h"

static id<AFCacheableItemDelegate> staticDebugDelegate;

@interface AFDebugHTTPURLProtocol : AFHTTPURLProtocol

+ (void)setDebugDelegate:(id<AFCacheableItemDelegate>)aDelegate;

@end
