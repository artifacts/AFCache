//
//  AFCacheableItem+MetaDescription.h
//  AFCache
//
//  Created by Michael Markowski on 16.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFCacheableItem.h"

@interface AFCacheableItem (Packaging)

- (NSString*)metaDescription;
- (NSString*)metaJSON;

+ (NSString *)urlEncodeValue:(NSString *)str;
- (void)setDataAndFile:(NSData*)theData;

@end
