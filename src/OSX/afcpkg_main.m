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

#define kDefaultMaxItemFileSize kAFCacheInfiniteFileSize


#pragma mark -
#pragma mark main

/* ================================================================================================
 * Main
 * ================================================================================================ */

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

#pragma mark -
#pragma mark commandline handling

- (void)enumerateFilesInFolder:(NSString*)aFolder processHiddenFiles:(BOOL)processHiddenFiles usingBlock:(void (^)(NSString *file, NSDictionary *fileAttributes))block
{
	
	NSFileManager *localFileManager=[[NSFileManager alloc] init];
	// A directory enumarator for iterating through a folder's files
	NSDirectoryEnumerator *dirEnum = [[localFileManager enumeratorAtPath:aFolder] retain];
	
	// write meta descriptions
	for (NSString *file in dirEnum) {
		// Create an inner autorelease pool, because we will create many objects in a loop
		NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
		NSDictionary *attributes = [dirEnum fileAttributes];
		NSString *fileType = [attributes objectForKey:NSFileType];
		BOOL hidden = [[file lastPathComponent] hasPrefix:@"."] || ([file rangeOfString:@"/."].location!=NSNotFound);
		
		if ([fileType isEqualToString:NSFileTypeRegular]) {
			if (!hidden || processHiddenFiles) {
				block(file, attributes);
			}
		}
		[innerPool drain];
	}
	[dirEnum release];
	[localFileManager release];
}

/* ================================================================================================
 * Create AFCache Package with given commandline args
 * ================================================================================================ */

- (void)createPackageWithArgs:(NSUserDefaults*)args {
	
	// folder containing resources
	self.folder = [args stringForKey:@"folder"];
	
	// base url, e.g. http://www.foo.bar (WITHOUT trailig slash)	
	self.baseURL = [args stringForKey:@"baseurl"];
	
	// max-age in seconds
	self.maxAge = [args stringForKey:@"maxage"];
	
	// Maximum filesize of a cacheable item. Default is unlimited.
	double maxItemFileSize = [args doubleForKey:@"maxItemFileSize"];
	if (maxItemFileSize == 0) {
		maxItemFileSize = kDefaultMaxItemFileSize;
	}
	[AFCache sharedInstance].maxItemFileSize = maxItemFileSize;
	
	// add n seconds to file's lastmodfied date
	if ([args doubleForKey:@"lastmodifiedminus"] > 0) {
		self.lastModifiedOffset = -1 * [args doubleForKey:@"lastmodifiedminus"];
	}
	
	// substract n seconds from file's lastmodfied date
	if ([args doubleForKey:@"lastmodifiedplus"] > 0) {
		self.lastModifiedOffset = [args doubleForKey:@"lastmodifiedplus"];
	}

	// write manifest file in json format (just for testing purposes)
	NSString *json = [args stringForKey:@"json"];

	// include all files. By default, files starting with a dot are excluded.
	NSString *addAllFiles = [args stringForKey:@"a"];

	// output filename
	NSString *outfile = [args stringForKey:@"outfile"];
	
	// Folder containing arbitrary user data (will be accesible via userDataPathForPackageArchiveKey: in AFCache+Packaging.m
	NSString *userDataFolder = [args stringForKey:@"userdata"];

	// Key under which userdata can be accessed. Default is no key.
	NSString *userDataKey = [args stringForKey:@"userdatakey"];
	
	// Create ZIP archive
	__block ZipArchive *zip = [[ZipArchive alloc] init];

	NSMutableString *result = [[NSMutableString alloc] init];
	BOOL showHelp = (!baseURL);
	@try {	
		if (showHelp==YES) {
			printf("\n");
			printf("Usage: afcpkg [-outfile] [-maxage] [-baseurl] [-file] [-folder] [-json] [-h] [-a] [-outfile] [-maxItemFileSize] [-userdata]\n");
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
			printf("\t-maxItemFileSize \t\t\tMaximum filesize of a cacheable item. Default is unlimited.\n");
			printf("\t-userdata \t\t\tFolder containing arbitrary user data (will be accesible via userDataPathForPackageArchiveKey: in AFCache+Packaging.m\n");
			printf("\t-userdatakey \t\t\tKey under which userdata can be accessed. Default is no key (nil).\n");
			printf("\n");
			exit(0);
		} else {
			if (!folder) folder = @".";
			// Create ZIP file or exit on error
			BOOL ret = [zip CreateZipFile2:(outfile)?outfile:@"afcache-archive.zip"];
			if (!ret) {
				printf("Failed creating zip file.\n");
				exit(1);
			}

			// Exit if given folder containing data doesn't exist
			NSFileManager *localFileManager=[[NSFileManager alloc] init];
			BOOL folderExists = [localFileManager fileExistsAtPath:folder];
			if (!folderExists) {
				printf("Folder '%s' does not exist. Aborting.\n", [folder cStringUsingEncoding:NSUTF8StringEncoding]);
				exit(0);
			}
			if (json) {
				[result appendFormat:@"{\n\"resources\":[\n"];
			}

			
			BOOL processHiddenFiles = ([addAllFiles length] > 0)?YES:NO;
			__block NSMutableArray *metaDescriptions = [[NSMutableArray alloc] init];
			
			[self enumerateFilesInFolder:folder processHiddenFiles:processHiddenFiles usingBlock: ^ (NSString *file, NSDictionary *fileAttributes) {
				NSDate *lastModificationDate = [fileAttributes objectForKey:NSFileModificationDate];
				NSString *fileType = [fileAttributes objectForKey:NSFileType];
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
						NSString *metaDescription = (json)?[item metaJSON]:[item metaDescription];						
						if (metaDescription) {
							[metaDescriptions addObject:metaDescription];
						}
						[item release];
					}
				}
								
			}];

			
			if ([userDataFolder length] > 0) {
				[self enumerateFilesInFolder:userDataFolder processHiddenFiles:processHiddenFiles usingBlock: ^ (NSString *file, NSDictionary *fileAttributes) {
					NSString *completePathToFile = [NSString stringWithFormat:@"%@/%@", userDataFolder, file];
					NSString *userDataPath = ([userDataKey length] > 0)?[NSString stringWithFormat:@"%@/%@", kAFCacheUserDataFolder, userDataKey]:kAFCacheUserDataFolder;
					NSString *filePathInZip = [NSString stringWithFormat:@"%@/%@", userDataPath, file];					
					printf("Adding userdata: %s\n", [filePathInZip cStringUsingEncoding:NSUTF8StringEncoding]);
					[zip addFileToZip:completePathToFile newname:filePathInZip];				
				}];
			}				

			if ([metaDescriptions count] == 0 && [userDataFolder length] == 0) {
				printf("No input files. Aborting.\n");
				exit(0);			
			}
			
			[localFileManager release];
			[result appendFormat:@"baseURL = %@\n", baseURL];
			
			// write meta descriptions into result string
			NSUInteger i = [metaDescriptions count];
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
	
	// Add manifest file to ZIP
	printf("Adding manifest.afcache\n");
	[zip addFileToZip:manifestPath newname:@"manifest.afcache"];

	// cleanup
	[zip release];
	[result release];
	[[NSFileManager defaultManager] removeItemAtPath:manifestPath error:&error];
}



#pragma mark -
#pragma mark cacheableItem creation

/* ================================================================================================
 * Create a new AFCacheableItem with file at path and a given last modification data
 * ================================================================================================ */

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
	return item;
}

- (void) dealloc
{
	[super dealloc];
}

@end
