//
//  AFPackageItemInfo.m
//  AFCache
//
//  Created by Michael Markowski on 28.01.11.
//  Copyright 2011 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFPackageInfo.h"


@implementation AFPackageInfo

@synthesize packageURL, baseURL, resourceURLs, userData;

- (id)init {
	self = [super init];
	if (self != nil) {
		resourceURLs = [[NSArray alloc] init];
		userData = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)encodeWithCoder: (NSCoder *) coder {
	[coder encodeObject: packageURL			forKey: @"AFPkgInfo_packageURL"];
	[coder encodeObject: baseURL			forKey: @"AFPkgInfo_baseURL"];
	[coder encodeObject: resourceURLs		forKey: @"AFPkgInfo_resourceURLs"];
	[coder encodeObject: userData			forKey: @"AFPkgInfo_userData"];
}

- (id)initWithCoder: (NSCoder *) coder {
	self.packageURL			= [coder decodeObjectForKey: @"AFPkgInfo_packageURL"];	
	self.baseURL			= [coder decodeObjectForKey: @"AFPkgInfo_baseURL"];	
	self.resourceURLs		= [coder decodeObjectForKey: @"AFPkgInfo_resourceURLs"];	
	self.userData			= [coder decodeObjectForKey: @"AFPkgInfo_userData"];	
	return self;
}

- (NSString*)description {
	NSMutableString *s = [NSMutableString stringWithString:@"Cache information:\n"];
	[s appendFormat:@"packageURL: %@\n",		packageURL];
	[s appendFormat:@"baseURL: %@\n",			baseURL];
	[s appendFormat:@"resourceURLs: %@\n",		[resourceURLs description]];
	[s appendFormat:@"userData: %@\n",			[userData description]];
	return s;
}

- (void) dealloc {
	[userData release];
	[packageURL release];
	[baseURL release];
	[resourceURLs release];
	
	[super dealloc];
}
@end
