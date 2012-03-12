//
//  AFHTTPURLProtocol.h
//  AFCache-iOS
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFCache.h"

@interface AFHTTPURLProtocol : NSURLProtocol <AFCacheableItemDelegate> {
    NSURLRequest *m_request;
}

@property (nonatomic, retain) NSURLRequest *request;

@end
