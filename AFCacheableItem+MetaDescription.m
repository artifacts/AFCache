//
//  AFCacheableItem+MetaDescription.m
//  AFCache
//
//  Created by Michael Markowski on 16.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCacheableItem+MetaDescription.h"
#import "DateParser.h"
#import "AFCache+PrivateExtensions.h"

@implementation AFCacheableItem (MetaDescription)

- (NSString*)metaDescription {
	NSMutableString *metaDescription = [NSMutableString string];
	NSString *filename = [[AFCache sharedInstance] filenameForURL:self.url];
	DateParser *parser = [[DateParser alloc] init];
	[metaDescription appendFormat:@"%@ %@ %@ %@",
	 self.url,
	 filename,
	 [DateParser formatHTTPDate:self.info.lastModified],
	 [DateParser formatHTTPDate:self.validUntil]];
	[parser release];
	return metaDescription;
}

@end
