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

- (NSString*)metaJSON {
	NSString *filename = [[AFCache sharedInstance] filenameForURL:self.url];
	DateParser *parser = [[DateParser alloc] init];
	NSMutableString *metaDescription = [NSMutableString stringWithFormat:@"{\"url\": \"%@\",\n\"file\": \"%@\",\n\"last-modified\": \"%@\"",
	 self.url,
	 filename,
	 [DateParser formatHTTPDate:self.info.lastModified],
	 [DateParser formatHTTPDate:self.validUntil]];
	if (self.validUntil) {
		[metaDescription appendFormat:@",\n\"expires\": \"%@\"", validUntil];
	}
	[metaDescription appendFormat:@"\n}"];
	[parser release];
	return metaDescription;
}

- (NSString*)metaDescription {
	//NSString *filename = [[AFCache sharedInstance] filenameForURL:self.url];
	DateParser *parser = [[DateParser alloc] init];
	NSMutableString *metaDescription = [NSMutableString stringWithFormat:@"%@ ; %@",
										self.url,										
										[DateParser formatHTTPDate:self.info.lastModified]];
	if (self.validUntil) {
		[metaDescription appendFormat:@" ; %@", [DateParser formatHTTPDate:self.validUntil]];
	}
	[metaDescription appendString:@"\n"];
	[parser release];
	return metaDescription;
}

@end
