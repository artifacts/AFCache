//
//  AFCacheableItem+MetaDescription.m
//  AFCache
//
//  Created by Michael Markowski on 16.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCacheableItem+Packaging.h"
#import "DateParser.h"
#import "AFCache+PrivateAPI.h"

@implementation AFCacheableItem (Packaging)

- (AFCacheableItem*)initWithURL:(NSURL*)URL
				  lastModified:(NSDate*)lastModified 
					expireDate:(NSDate*)expireDate
{	
	self = [super init];
	self.info = [[[AFCacheableItemInfo alloc] init] autorelease];
	info.lastModified = lastModified;
	info.expireDate = expireDate;
	self.url = URL;	
	self.cacheStatus = kCacheStatusFresh;
	self.validUntil = info.expireDate;
	self.cache = [AFCache sharedInstance];	
	return self;
}

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

+ (NSString *)urlEncodeValue:(NSString *)str
{
	CFStringRef preprocessedString =CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)str, CFSTR(""), kCFStringEncodingUTF8);
	CFStringRef urlString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, preprocessedString, NULL, NULL, kCFStringEncodingUTF8);
//	CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, urlString, NULL);	
	CFRelease(preprocessedString);
    return [(NSString*)urlString autorelease];
}

- (void)setDataAndFile:(NSData*)theData {
	[self setContentLength:[theData length]];
	[self setDownloadStartedFileAttributes];
	self.data = theData;
	self.fileHandle = [cache createFileForItem:self];
    [self.fileHandle seekToFileOffset:0];
    [self.fileHandle writeData:theData];
	[self setDownloadFinishedFileAttributes];
    [self.fileHandle closeFile];
    self.fileHandle = nil;
}	

@end
