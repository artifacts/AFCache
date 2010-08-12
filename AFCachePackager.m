//
//  AFCachePackager.m
//  AFCache
//
//  Created by Michael Markowski on 16.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCachePackager.h"

@implementation AFCachePackager

- (AFCacheableItem*)newCacheableItemFromFileAtPath:(NSString*)path 
										   withURL:(NSURL*)URL
									  lastModified:(NSDate*)lastModified 
										expireDate:(NSDate*)expireDate
{	
	AFCacheableItemInfo *info = [[[AFCacheableItemInfo alloc] init] autorelease];
	info.lastModified = lastModified;
	info.expireDate = expireDate;
	AFCacheableItem *item = [[AFCacheableItem alloc] init];
	item.url = URL;
	item.info = info;
	[info release];
	item.data = [NSData dataWithContentsOfMappedFile:path];
	if (!item.data)
    {
        [item release];
        return nil;
    }
	item.cacheStatus = kCacheStatusFresh;
	item.validUntil = info.expireDate;
	item.cache = [AFCache sharedInstance];
	return item;
}

@end
