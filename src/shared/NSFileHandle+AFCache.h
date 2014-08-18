//
//  NSFileHandle+AFCache.h
//  AFCache
//
//  Created by Lars Blumberg on 15.08.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSFileHandle (AFCache)

- (void)flagAsDownloadStartedWithContentLength: (uint64_t)contentLength;

- (void)flagAsDownloadFinishedWithContentLength: (uint64_t)contentLength;

@end
