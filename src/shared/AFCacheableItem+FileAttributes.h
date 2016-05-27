//
//  AFCacheableItem+FileAttributes.h
//  AFCache
//
//  Created by Sebastian Grimme on 17.05.16.
//  Copyright © 2016 Artifacts - Fine Software Development. All rights reserved.
//

#import <AFCache/AFCache.h>

extern const char* kAFCacheContentLengthFileAttribute;
extern const char* kAFCacheDownloadingFileAttribute;

@interface AFCacheableItem (FileAttributes)
- (BOOL)hasDownloadFileAttribute;
- (void)flagAsDownloadStartedWithContentLength:(uint64_t)contentLength;
- (void)flagAsDownloadFinishedWithContentLength:(uint64_t)contentLength;
- (uint64_t)getContentLengthFromFile;
@end
