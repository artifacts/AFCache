//
//  AFCacheableItem+FileAttributes.m
//  AFCache
//
//  Created by Sebastian Grimme on 17.05.16.
//  Copyright © 2016 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCacheableItem+FileAttributes.h"

#import "AFCache+PrivateAPI.h"
#import "AFCache_Logging.h"
#import "AFCacheableItem.h"
#include <sys/xattr.h>

const char* kAFCacheContentLengthFileAttribute = "de.artifacts.contentLength";
const char* kAFCacheDownloadingFileAttribute = "de.artifacts.downloading";

@implementation AFCacheableItem (FileAttributes)

- (BOOL)hasDownloadFileAttribute {
    unsigned int downloading = 0;
    NSString *filePath = [self.cache fullPathForCacheableItem:self];
    return sizeof(downloading) == getxattr([filePath fileSystemRepresentation], kAFCacheDownloadingFileAttribute, &downloading, sizeof(downloading), 0, 0);
}

- (void)flagAsDownloadStartedWithContentLength:(uint64_t)contentLength {
    NSString *filePath = [self.cache fullPathForCacheableItem:self];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return;
    }
    if (0 != setxattr(filePath.fileSystemRepresentation, kAFCacheContentLengthFileAttribute, &contentLength, sizeof(uint64_t), 0, 0)) {
        AFLog(@"Could not set contentLength attribute on %@", self);
    }
    unsigned int downloading = 1;
    if (0 != setxattr(filePath.fileSystemRepresentation, kAFCacheDownloadingFileAttribute, &downloading, sizeof(downloading), 0, 0)) {
        AFLog(@"Could not set downloading attribute on %@", self);
    }
}

- (void)flagAsDownloadFinishedWithContentLength:(uint64_t)contentLength {
    NSString *filePath = [self.cache fullPathForCacheableItem:self];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return;
    }
    if (0 != setxattr(filePath.fileSystemRepresentation, kAFCacheContentLengthFileAttribute, &contentLength, sizeof(uint64_t), 0, 0)) {
        AFLog(@"Could not set contentLength attribute on %@, errno = %ld", self, (long)errno );
    }
    if (0 != removexattr(filePath.fileSystemRepresentation, kAFCacheDownloadingFileAttribute, 0)) {
        AFLog(@"Could not remove downloading attribute on %@, errno = %ld", self, (long)errno );
    }
}

- (uint64_t)getContentLengthFromFile {
    if ([self isQueuedOrDownloading]) {
        return 0LL;
    }
    
    NSString *filePath = [self.cache fullPathForCacheableItem:self];
    
    uint64_t realContentLength = 0LL;
    ssize_t const size = getxattr([filePath fileSystemRepresentation],
                                  kAFCacheContentLengthFileAttribute,
                                  &realContentLength,
                                  sizeof(realContentLength),
                                  0, 0);
    if (sizeof(realContentLength) != size) {
        AFLog(@"Could not get content length attribute from file %@. This may be bad (errno = %ld", filePath, (long)errno);
        return 0LL;
    }
    return realContentLength;
}

@end
