//
//  AFCachePackager.h
//  AFCache
//
//  Created by Michael Markowski on 16.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFCache+PrivateExtensions.h"
#import "AFCacheableItem.h"

@interface AFCachePackager : NSObject {

}

- (AFCacheableItem*)newCacheableItemFromFileAtPath:(NSString*)path 
										   withURL:(NSURL*)absoluteURL 
									  lastModified:(NSDate*)lastModified 
										expireDate:(NSDate*)expireDate;

@end
