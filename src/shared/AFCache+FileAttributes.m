//
//  AFCache+FileAttributes.m
//  AFCache
//
//  Created by Sebastian Grimme on 17.05.16.
//  Copyright © 2016 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCache+FileAttributes.h"

#import "AFCacheableItem+FileAttributes.h"
#import "AFCache+PrivateAPI.h"
#import "AFCache_Logging.h"
#include <sys/xattr.h>

@implementation AFCache (FileAttributes)

- (uint64_t)setContentLengthForFileAtPath:(NSString*)filePath {
    NSError* err = nil;
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&err];
    if (err) {
        AFLog(@"Could not get file attributes for %@", filename);
        return 0;
    }
    uint64_t fileSize = [attrs fileSize];
    if (0 != setxattr(filePath.fileSystemRepresentation, kAFCacheContentLengthFileAttribute, &fileSize, sizeof(fileSize), 0, 0)) {
        AFLog(@"Could not set content length for file %@", filename);
        return 0;
    }
    return fileSize;
}

@end
