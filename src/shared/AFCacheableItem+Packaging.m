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
#import "NSFileHandle+AFCache.h"

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
    if (self.validUntil) {
        // TODO: A getter is not supposed to modify internal states. This is unexpected.
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

- (void)setDataAndFile:(NSData*)data {
	self.data = data;
	self.info.contentLength = [data length];

    // Store data into file
    NSFileHandle* fileHandle = [self.cache createFileForItem:self];
    [fileHandle seekToFileOffset:0];
    [fileHandle writeData:data];
    [fileHandle flagAsDownloadFinishedWithContentLength:[data length]];
    [fileHandle closeFile];
}

@end
