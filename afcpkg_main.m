//
//  afcpkg_main.m
//  AFCache
//
//  Created by Michael Markowski on 22.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "afcpkg_main.h"
#import "AFCache.h"
#import "AFCacheableItem+MetaDescription.h"

#import <Cocoa/Cocoa.h>

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *args = [NSUserDefaults standardUserDefaults];
	afcpkg_main *main = [[afcpkg_main alloc] init];
	
	[main createPackageWithArgs:args];
	[main release];
    [pool release];
    return 0;
}

@implementation afcpkg_main

@synthesize folder, baseURL, maxAge, packager, lastModifiedOffset;

- (id) init
{
	self = [super init];
	if (self != nil) {
		self.packager = [[AFCachePackager alloc] init];
	}
	return self;
}

- (void)createPackageWithArgs:(NSUserDefaults*)args {
	self.folder = [args stringForKey:@"folder"];
	self.baseURL = [args stringForKey:@"baseurl"];
	self.maxAge = [args stringForKey:@"maxage"];
	if ([args doubleForKey:@"lastmodifiedminus"] > 0) {
		self.lastModifiedOffset = -1 * [args doubleForKey:@"lastmodifiedminus"];
	}
	if ([args doubleForKey:@"lastmodifiedplus"] > 0) {
		self.lastModifiedOffset = [args doubleForKey:@"lastmodifiedplus"];
	}
	//NSString *filename = [args stringForKey:@"file"];
	NSString *help = [args stringForKey:@"h"];
	NSString *json = [args stringForKey:@"json"];
	NSString *addAllFiles = [args stringForKey:@"a"];
	NSString *outfile = [args stringForKey:@"outfile"];
	ZipArchive *zip = [[ZipArchive alloc] init];
	NSMutableString *result = [[NSMutableString alloc] init];
	
	@try {	
		if (help) {
			printf("Usage: afcpkg [-outfile] [-maxage] [-baseurl] [-file] [-folder] [-json] [-h] [-a]\n");
			printf("-maxage \t max-age in seconds");
			printf("-baseurl \t base url, e.g. http://www.foo.bar/");
			printf("-lastmodifiedplus add n seconds to file's lastmodfied date");
			printf("-lastmodifiedminus substract n seconds from file's lastmodfied date");
			printf("-folder \t folder containing resources");
			printf("-json write manifest file in json format");
			printf("-h display this help output");
			printf("-a include all files. By default, files starting with a dot are excluded.");
			printf("-o output filename");
			exit(0);
		} else {			
			if (!folder) folder = @".";
			BOOL ret = [zip CreateZipFile2:(outfile)?outfile:@"afcache-archive.zip"];
			if (!ret) {
				printf("Failed creating zip file.");
				exit(1);
			}
			NSFileManager *localFileManager=[[NSFileManager alloc] init];
			NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtPath:folder];
			NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
			NSString *metaDescription;
			
			if (json) {
				[result appendFormat:@"{\n\"resources\":[\n"];
			}

			NSMutableArray *metaDescriptions = [[NSMutableArray alloc] init];
			for (NSString *file in dirEnum) {
				NSDictionary *attributes = [dirEnum fileAttributes];
				NSDate *lastModificationDate = [attributes objectForKey:NSFileModificationDate];
				NSString *fileType = [attributes objectForKey:NSFileType];
				if ([fileType isEqualToString:NSFileTypeRegular]) {
					if (![file hasPrefix:@"."] || addAllFiles) {
						if (lastModifiedOffset != 0) {
							lastModificationDate = [lastModificationDate dateByAddingTimeInterval:lastModifiedOffset];
						}						
						AFCacheableItem *item = [self newCacheableItemForFileAtPath:file lastModified:lastModificationDate];
						NSString *completePathToFile = [NSString stringWithFormat:@"%@/%@", folder, file];
						printf("Adding %s\n", [item.filename cStringUsingEncoding:NSUTF8StringEncoding]);
						[zip addFileToZip:completePathToFile newname:item.filename];
						metaDescription = (json)?[item metaJSON]:[item metaDescription];						
						if (metaDescription) {
							[metaDescriptions addObject:metaDescription];
						}
						[item release];
					}
				}
				[innerPool release];
				innerPool = [[NSAutoreleasePool alloc] init];
			}
			[innerPool release];
			innerPool = nil;
			[localFileManager release];
			int i = [metaDescriptions count];
			for (NSString *desc in metaDescriptions) {
				if (json) {
					[result appendString:@"\t"];
				}
				[result appendFormat:@"%@", desc];
				if (json && i>1) {
					[result appendString:@",\n"];
				}
				i--;
			}
			[metaDescriptions release];
			
			if (json) {
				[result appendString: @"]\n}"];
			}
			//printf("\n%s\n\n", [result UTF8String]);			
			i++;
		}	
	}
	@catch (NSException * e) {
		NSLog(@"afcpkg error: %@", [e description]);
		printf("Error. See log for details.");
	}
	@finally {
		
	}
	
	// create manifest tmp file
	
	char *template = "/tmp/AFCache.XXXXXX";
    char *buffer = malloc(strlen(template) + 1);
    strcpy(buffer, template);
    mktemp(buffer);
    NSString *manifestPath = [NSString stringWithFormat:@"%s", buffer];
    free(buffer);
	
	NSError *error;
	BOOL ok = [result writeToFile:manifestPath atomically:YES
						 encoding:NSASCIIStringEncoding error:&error];
	if (!ok) {
		printf("Error writing file at %s\n%s", [manifestPath cStringUsingEncoding:NSUTF8StringEncoding], [[error localizedFailureReason] cStringUsingEncoding:NSUTF8StringEncoding]);
		exit(1);
	}
	
	printf("Adding manifest.afcache\n");
	[zip addFileToZip:manifestPath newname:@"manifest.afcache"];
	[zip release];
	[result release];
	[[NSFileManager defaultManager] removeItemAtPath:manifestPath error:&error];
}

//- (NSString*)metaDescriptionForFileAtPath:(NSString*)filepath lastModified:(NSDate*)lastModified json:(BOOL)json {
- (AFCacheableItem*)newCacheableItemForFileAtPath:(NSString*)filepath lastModified:(NSDate*)lastModified {	
	NSURL *url;
	NSString* escapedUrlString = [filepath stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
	
	if (baseURL) {
		url = [[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", baseURL, escapedUrlString]] retain];
	} else {
		url = [[NSURL URLWithString:[NSString stringWithFormat:@"afcpkg://localhost/%@", escapedUrlString]] retain];
	}
	NSDate *expireDate = nil;
	if (maxAge) {
		NSTimeInterval seconds = [maxAge doubleValue];
		expireDate = [lastModified dateByAddingTimeInterval:seconds];
	}
	NSString *completePathToFile = [NSString stringWithFormat:@"%@/%@", folder, filepath];
	AFCacheableItem *item = [packager newCacheableItemFromFileAtPath:completePathToFile 
															 withURL:url 
														lastModified:lastModified expireDate:expireDate];
	[url release];
	//NSLog(@"%@ ", filepath);
	return item;
}

- (void) dealloc
{
	[packager release];
	[super dealloc];
}

@end
