//
//  AFCache+FileAttributes.h
//  AFCache
//
//  Created by Sebastian Grimme on 17.05.16.
//  Copyright © 2016 Artifacts - Fine Software Development. All rights reserved.
//

#import <AFCache/AFCache.h>

@interface AFCache (FileAttributes)
- (uint64_t)setContentLengthForFileAtPath:(NSString*)filePath;
@end
