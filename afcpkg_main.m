//
//  afcpkg_main.m
//  AFCache
//
//  Created by Michael Markowski on 22.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "afcpkg_main.h"
#import "AFCache.h"
#import "AFCache+Packaging.h"
#import "AFCacheableItem+Packaging.h"

#import <Cocoa/Cocoa.h>

#define kDefaultMaxItemFileSize 500000

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

@synthesize folder, baseURL, maxAge, lastModifiedOffset;

- (void)createPackageWithArgs:(NSUserDefaults*)args {
	self.folder = [args stringForKey:@"folder"];
	self.baseURL = [args stringForKey:@"baseurl"];
	self.maxAge = [args stringForKey:@"maxage"];
	double maxItemFileSize = [args doubleForKey:@"maxItemFileSize"];
	if (maxItemFileSize == 0) {
		maxItemFileSize = kDefaultMaxItemFileSize;
	}
	[AFCache sharedInstance].maxItemFileSize = maxItemFileSize;
	if ([args doubleForKey:@"lastmodifiedminus"] > 0) {
		self.lastModifiedOffset = -1 * [args doubleForKey:@"lastmodifiedminus"];
	}
	if ([args doubleForKey:@"lastmodifiedplus"] > 0) {
		self.lastModifiedOffset = [args doubleForKey:@"lastmodifiedplus"];
	}
	//NSString *filename = [args stringForKey:@"file"];
//	NSString *help = [args stringForKey:@"h"];
	NSString *json = [args stringForKey:@"json"];
	NSString *addAllFiles = [args stringForKey:@"a"];
	NSString *outfile = [args stringForKey:@"outfile"];
	ZipArchive *zip = [[ZipArchive alloc] init];
	NSMutableString *result = [[NSMutableString alloc] init];
	BOOL showHelp = (!baseURL);
	@try {	
		if (showHelp==YES) {
			printf("\n");
			printf("Usage: afcpkg [-outfile] [-maxage] [-baseurl] [-file] [-folder] [-json] [-h] [-a]\n");
			printf("\n");
			printf("\t-maxage \t\tmax-age in seconds\n");
			printf("\t-baseurl \t\tbase url, e.g. http://www.foo.bar (WITHOUT trailig slash)\n");
			printf("\t-lastmodifiedplus \tadd n seconds to file's lastmodfied date\n");
			printf("\t-lastmodifiedminus \tsubstract n seconds from file's lastmodfied date\n");
			printf("\t-folder \t\tfolder containing resources\n");
			printf("\t-json \t\t\twrite manifest file in json format (just for testing purposes)\n");
			printf("\t-h \t\t\tdisplay this help output\n");
			printf("\t-a \t\t\tinclude all files. By default, files starting with a dot are excluded.\n");
			printf("\t-outfile \t\t\toutput filename\n");
			printf("\t-maxItemFileSize \t\t\tMaximum filesize of a cacheable item\n");
			printf("\t-userdata \t\t\tFolder containing arbitrary user data (will be accesible via userDataPathForPackageArchiveKey: in AFCache+Packaging.m\n");
			printf("\n");
			exit(0);
		} else {
			if (!folder) folder = @".";
			BOOL ret = [zip CreateZipFile2:(outfile)?outfile:@"afcache-archive.zip"];
			if (!ret) {
				printf("Failed creating zip file.\n");
				exit(1);
			}
			NSFileManager *localFileManager=[[NSFileManager alloc] init];
			BOOL folderExists = [localFileManager fileExistsAtPath:folder];
			if (!folderExists) {
				printf("Folder '%s' does not exist. Aborting.\n", [folder cStringUsingEncoding:NSUTF8StringEncoding]);
				exit(0);
			}
			NSDirectoryEnumerator *dirEnum = [localFileManager enumeratorAtPath:folder];
			NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
			NSString *metaDescription;
			
			if (json) {
				[result appendFormat:@"{\n\"resources\":[\n"];
			}

			NSMutableArray *metaDescriptions = [[NSMutableArray alloc] init];
			if (!dirEnum) {
				printf("No input files. Aborting.\n");
				exit(0);			
			}
			
			for (NSString *file in dirEnum) {
				NSDictionary *attributes = [dirEnum fileAttributes];
				NSDate *lastModificationDate = [attributes objectForKey:NSFileModificationDate];
				NSString *fileType = [attributes objectForKey:NSFileType];
				BOOL hidden = [[file lastPathComponent] hasPrefix:@"."] || ([file rangeOfString:@"/."].location!=NSNotFound);
				
				if ([fileType isEqualToString:NSFileTypeRegular]) {
					if (!hidden || addAllFiles) {
						if (lastModifiedOffset != 0) {
							lastModificationDate = [lastModificationDate dateByAddingTimeInterval:lastModifiedOffset];
						}						
						AFCacheableItem *item = [self newCacheableItemForFileAtPath:file lastModified:lastModificationDate];
						NSString *completePathToFile = [NSString stringWithFormat:@"%@/%@", folder, file];
						printf("Adding %s\n", [item.filename cStringUsingEncoding:NSUTF8StringEncoding]); //, [file cStringUsingEncoding:NSUTF8StringEncoding]);
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

- (AFCacheableItem*)newCacheableItemForFileAtPath:(NSString*)filepath lastModified:(NSDate*)lastModified {	
	NSURL *url;	
	NSString* escapedUrlString = [AFCacheableItem urlEncodeValue:filepath];
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
	AFCacheableItem *item = [[AFCacheableItem alloc] initWithURL:url lastModified:lastModified expireDate:expireDate];
	NSData *data = [NSData dataWithContentsOfMappedFile:completePathToFile];
	[item setDataAndFile:data];
	[url release];
	//NSLog(@"%@ ", filepath);
	return item;
}

- (void) dealloc
{
	[super dealloc];
}

@end
