//
//  NSFileHandle+AFCache.m
//  AFCache
//
//  Created by Lars Blumberg on 15.08.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#include <sys/xattr.h>
#import <AFCache/AFCache.h>
#import "NSFileHandle+AFCache.h"
#import "AFCache_Logging.h"

//const char* kAFCacheContentLengthFileAttribute = "de.artifacts.contentLength";
//const char* kAFCacheDownloadingFileAttribute = "de.artifacts.downloading";

@implementation NSFileHandle (AFCache)

- (void)flagAsDownloadStartedWithContentLength: (uint64_t)contentLength {
    int fd = [self fileDescriptor];
    if (fd <= 0) {
        return;
    }
    if (0 != fsetxattr(fd, kAFCacheContentLengthFileAttribute, &contentLength, sizeof(uint64_t), 0, 0)) {
        AFLog(@"Could not set contentLength attribute on %@", self);
    }
    unsigned int downloading = 1;
    if (0 != fsetxattr(fd, kAFCacheDownloadingFileAttribute, &downloading, sizeof(downloading), 0, 0)) {
        AFLog(@"Could not set downloading attribute on %@", self);
    }
}

- (void)flagAsDownloadFinishedWithContentLength: (uint64_t)contentLength {
    int fd = [self fileDescriptor];
    if (fd <= 0) {
        return;
    }
    if (0 != fsetxattr(fd, kAFCacheContentLengthFileAttribute, &contentLength, sizeof(uint64_t), 0, 0)) {
        AFLog(@"Could not set contentLength attribute on %@, errno = %ld", self, (long)errno );
    }
    if (0 != fremovexattr(fd, kAFCacheDownloadingFileAttribute, 0)) {
        AFLog(@"Could not remove downloading attribute on %@, errno = %ld", self, (long)errno );
    }
}

@end
