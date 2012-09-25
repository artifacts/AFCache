//
//  AFCachePackageCreator.m
//  AFCache
//
//  Created by Michael Markowski on 22.03.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCachePackageCreator.h"
#import "ZipArchive.h"

#define kDefaultMaxItemFileSize kAFCacheInfiniteFileSize

@implementation AFCachePackageCreator

/* ================================================================================================
 * Create a new AFCacheableItem with file at path and a given last modification data
 * ================================================================================================ */

- (AFCacheableItem*)newCacheableItemForFileAtPath:(NSString*)filepath lastModified:(NSDate*)lastModified baseURL:(NSString*)baseURL maxAge:(NSNumber*)maxAge baseFolder:(NSString*)folder {	
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

- (BOOL)createPackageWithOptions:(NSDictionary*)options error:(NSError**)inError {
    NSError *error = *inError;    
    NSString *folder;
	NSString *baseURL;
	NSNumber *maxAge;
	NSTimeInterval lastModifiedOffset;
    BOOL success = YES;
    
	// folder containing resources
	folder = [options valueForKey:kPackagerOptionResourcesFolder];
	
	// base url, e.g. http://www.foo.bar (WITHOUT trailig slash)	
	baseURL = [options valueForKey:kPackagerOptionBaseURL];
	if ([baseURL hasSuffix:@"/"]) {
        baseURL = [baseURL substringToIndex:[baseURL length] -1];
    }
	// max-age in seconds
	maxAge = [NSNumber numberWithDouble:[[options valueForKey:kPackagerOptionMaxAge] doubleValue]];
	
	// Maximum filesize of a cacheable item. Default is unlimited.
	double maxItemFileSize = [[options valueForKey:kPackagerOptionMaxItemFileSize] doubleValue];
	if (maxItemFileSize == 0) {
		maxItemFileSize = kDefaultMaxItemFileSize;
	}
#if MAINTAINER_WARNINGS
#warning not good to change the max item file size in the cache singleton then calling this method!
#endif
	[AFCache sharedInstance].maxItemFileSize = maxItemFileSize;
	
	// add n seconds to file's lastmodfied date
	if ([[options valueForKey:kPackagerOptionLastModifiedMinus] doubleValue] > 0) {
		lastModifiedOffset = -1 * [[options valueForKey:kPackagerOptionLastModifiedMinus] doubleValue];
	}
	
	// substract n seconds from file's lastmodfied date
	if ([[options valueForKey:kPackagerOptionLastModifiedPlus] doubleValue] > 0) {
		lastModifiedOffset = [[options valueForKey:kPackagerOptionLastModifiedPlus] doubleValue];
	}
    
	// write manifest file in json format (just for testing purposes)
	NSString *json = [options valueForKey:kPackagerOptionOutputFormatJSON];
    
	// include all files. By default, files starting with a dot are excluded.
	NSString *addAllFiles = [options valueForKey:kPackagerOptionIncludeAllFiles];
    
	// output filename
	NSString *outfile = [options valueForKey:kPackagerOptionOutputFilename];
	
	// Folder containing arbitrary user data (will be accesible via userDataPathForPackageArchiveKey: in AFCache+Packaging.m
	NSString *userDataFolder = [options valueForKey:kPackagerOptionUserDataFolder];
    
	// Key under which userdata can be accessed. Default is no key.
	NSString *userDataKey = [options valueForKey:kPackagerOptionUserDataKey];
	
    NSDictionary *fileToURLMap = [options valueForKey:kPackagerOptionFileToURLMap];
    
	// Create ZIP archive
	__block ZipArchive *zip = [[ZipArchive alloc] init];
    
	NSMutableString *result = [[NSMutableString alloc] init];
	@try {
			if (!folder) folder = @".";
			// Create ZIP file or exit on error
			BOOL ret = [zip CreateZipFile2:(outfile)?outfile:@"afcache-archive.zip"];
			if (!ret) {
				NSLog(@"Failed creating zip file.\n");
                success = NO;
                goto bailout;
			}
            
			// Exit if given folder containing data doesn't exist
			NSFileManager *localFileManager=[[NSFileManager alloc] init];
			BOOL folderExists = [localFileManager fileExistsAtPath:folder];
			if (!folderExists) {
				NSLog(@"Folder '%s' does not exist. Aborting.\n", [folder cStringUsingEncoding:NSUTF8StringEncoding]);
                success = NO;
                goto bailout;
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
						AFCacheableItem *item = [self newCacheableItemForFileAtPath:file lastModified:lastModificationDate baseURL:baseURL maxAge:maxAge baseFolder:folder];
                        NSString *mappedURL = [fileToURLMap valueForKey:item.info.filename];
                        if (mappedURL) {
                            item.url = [NSURL URLWithString:mappedURL];
                        }
						NSString *completePathToFile = [NSString stringWithFormat:@"%@/%@", folder, file];
						NSLog(@"Adding %s\n", [item.info.filename cStringUsingEncoding:NSUTF8StringEncoding]); //, [file cStringUsingEncoding:NSUTF8StringEncoding]);
						[zip addFileToZip:completePathToFile newname:item.info.filename];
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
                success = NO;
                goto bailout;			
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
	@catch (NSException * e) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[e description] forKey:NSLocalizedDescriptionKey];
        error = [NSError errorWithDomain:@"AFCache" code:99 userInfo:userInfo];
        success = NO;
        goto bailout;
	}
	
	// create manifest tmp file	
	const char *template = (char*)[[NSTemporaryDirectory() stringByAppendingPathComponent:@"AFCache.XXXXXX"] UTF8String];
    char *buffer = strdup(template);
    mktemp(buffer);
    NSString *manifestPath = [NSString stringWithFormat:@"%s", buffer];
    free(buffer);

	BOOL ok = [result writeToFile:manifestPath atomically:YES
						 encoding:NSASCIIStringEncoding error:&error];
	if (!ok) {
        NSDictionary *userInfo = [NSDictionary dictionaryWithObject: [NSString stringWithFormat: @"Error writing file at %s\n%@", 
                                                                      [manifestPath cStringUsingEncoding:NSUTF8StringEncoding], 
                                                                      [error localizedFailureReason]]
                                                             forKey:NSLocalizedDescriptionKey];
        error = [NSError errorWithDomain:@"AFCache" code:0 userInfo:userInfo];
        success = NO;
        goto bailout;
	}
	
	[zip addFileToZip:manifestPath newname:@"manifest.afcache"];
    
	// cleanup
	[zip release];
	[result release];
	[[NSFileManager defaultManager] removeItemAtPath:manifestPath error:&error];
bailout:
    return success;
}

@end
