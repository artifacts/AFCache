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

- (AFCacheableItem*)initWithURL:(NSURL*)URL
           lastModified:(NSDate*)lastModified 
           expireDate:(NSDate*)expireDate
          contentType:(NSString*)contentType;

- (AFCacheableItem*)initWithURL:(NSURL*)URL
				  lastModified:(NSDate*)lastModified 
					expireDate:(NSDate*)expireDate;

- (NSString*)metaDescription;
- (NSString*)metaJSON;

+ (NSString *)urlEncodeValue:(NSString *)str;
- (void)setDataAndFile:(NSData*)theData;

@end
