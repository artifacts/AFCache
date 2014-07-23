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

- (NSString*)metaJSON {
    DateParser* dateParser = [[DateParser alloc] init];
	NSString *filename = self.info.filename;
	DateParser *parser = [[DateParser alloc] init];
	NSMutableString *metaDescription = [NSMutableString stringWithFormat:@"{\"url\": \"%@\",\n\"file\": \"%@\",\n\"last-modified\": \"%@\", valid until: %@",
	 self.url,
	 filename,
	 [dateParser formatHTTPDate:self.info.lastModified],
	 [dateParser formatHTTPDate:self.validUntil]];
	if (self.validUntil) {
		[metaDescription appendFormat:@",\n\"expires\": \"%@\"", self.validUntil];
	}
	[metaDescription appendFormat:@"\n}"];
	return metaDescription;
}

- (NSString*)metaDescription {
    DateParser* dateParser = [[DateParser alloc] init];
	DateParser *parser = [[DateParser alloc] init];
    if (self.validUntil) {
        self.validUntil = self.info.lastModified;
    }
	NSMutableString *metaDescription = [NSMutableString stringWithFormat:@"%@ ; %@ ; %@ ; %@ ; %@",
										self.url,										
										[dateParser formatHTTPDate:self.info.lastModified],
                                        self.validUntil?[dateParser formatHTTPDate:self.validUntil]:@"NULL",
                                        self.info.mimeType?:@"NULL",
                                        self.info.filename];
	[metaDescription appendString:@"\n"];
	return metaDescription;
}

+ (NSString *)urlEncodeValue:(NSString *)str
{
	CFStringRef preprocessedString =CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault, (CFStringRef)str, CFSTR(""), kCFStringEncodingUTF8);
	CFStringRef urlString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, preprocessedString, NULL, NULL, kCFStringEncodingUTF8);
	CFRelease(preprocessedString);
    return (__bridge NSString*)urlString;
}

- (void)setDataAndFile:(NSData*)theData {
	[self.info setContentLength:[theData length]];
	[self setDownloadStartedFileAttributes];
	self.data = theData;
	self.fileHandle = [self.cache createFileForItem:self];
    [self.fileHandle seekToFileOffset:0];
    [self.fileHandle writeData:theData];
	[self setDownloadFinishedFileAttributes];
    [self.fileHandle closeFile];
    self.fileHandle = nil;
}	

@end
