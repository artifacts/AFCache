//
//  AFCache+Packaging.m
//  AFCache
//
//  Created by Michael Markowski on 13.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#include <sys/xattr.h>
#import "AFCache+PrivateAPI.h"
#import "AFCacheableItem+Packaging.h"
#import "ZipArchive.h"
#import "DateParser.h"
#import "AFPackageInfo.h"
#import "AFCache+Packaging.h"
#import "AFCache_Logging.h"
@interface AFCache (Packaging_private)
+(BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)URL;
@end

@implementation AFCache (Packaging)

enum ManifestKeys {
	ManifestKeyURL = 0,
	ManifestKeyLastModified = 1,
	ManifestKeyExpires = 2,
	ManifestKeyMimeType = 3,
    ManifestKeyFilename = 4,
};

- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate {
	AFCacheableItem *item = [self cachedObjectForURL:url
											delegate:aDelegate
											selector:@selector(packageArchiveDidFinishLoading:)
									 didFailSelector:@selector(packageArchiveDidFailLoading:)
											 options:kAFCacheIsPackageArchive | kAFCacheRevalidateEntry
											userData:nil
											username:nil
											password:nil request:nil];
	return item;
}

- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate username: (NSString*) username password: (NSString*) password {
	AFCacheableItem *item = [self cachedObjectForURL: url 
											delegate: aDelegate 
											selector: @selector(packageArchiveDidFinishLoading:)
									 didFailSelector:  @selector(packageArchiveDidFailLoading:)
											 options: kAFCacheIsPackageArchive | kAFCacheRevalidateEntry
											userData: nil
											username: username
											password: password request:nil];
	return item;
}

- (void) packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem {
	if ([cacheableItem.delegate respondsToSelector:@selector(packageArchiveDidFinishLoading:)]) {
		[cacheableItem.delegate performSelector:@selector(packageArchiveDidFinishLoading:) withObject:cacheableItem];
	}	
}

/*
 * Consume (unzip an archive) and optionally keep track of the included items.
 * Preserve package info is given as an argument to the unzip thread.
 * If YES, AFCache remembers which items have been imported for this package URL.
 * Package information can be accessed later via packageInfoForURL:
 */

- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem preservePackageInfo:(BOOL)preservePackageInfo {
	[self consumePackageArchive:cacheableItem userData:nil preservePackageInfo:preservePackageInfo];
}

- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem userData:(NSDictionary*)userData preservePackageInfo:(BOOL)preservePackageInfo {
    if (cacheableItem.info.packageArchiveStatus == kAFCachePackageArchiveStatusConsumed) {
        // ZIP file is already consumed
        [self performArchiveReadyWithItem:cacheableItem];
        return;
    }
	NSString *urlCacheStorePath = self.dataPath;
	NSString *pathToZip = [[AFCache sharedInstance] fullPathForCacheableItem:cacheableItem];
	
	NSDictionary* arguments = @{
            @"pathToZip" : pathToZip,
            @"cacheableItem" : cacheableItem,
            @"urlCacheStorePath" : urlCacheStorePath,
            @"preservePackageInfo" : @(preservePackageInfo),
            @"userData" : userData};
	
	[[self packageArchiveQueue] addOperation:[[NSInvocationOperation alloc] initWithTarget:self
                                                                            selector:@selector(unzipWithArguments:)
                                                                              object:arguments]];
}


- (void)unzipWithArguments:(NSDictionary*)arguments {
	@autoreleasepool {
    
        AFLog(@"starting to unzip archive");
	
        // get arguments from dictionary
        NSString* pathToZip				= arguments[@"pathToZip"];
        AFCacheableItem* cacheableItem	= arguments[@"cacheableItem"];
        __unsafe_unretained NSString* urlCacheStorePath = arguments[@"urlCacheStorePath"];
	    BOOL preservePackageInfo		= [arguments[@"preservePackageInfo"] boolValue];
	    NSDictionary *userData			= arguments[@"userData"];

        ZipArchive *zip = [[ZipArchive alloc] init];
        BOOL success = [zip UnzipOpenFile:pathToZip];
        [zip UnzipFileTo:[pathToZip stringByDeletingLastPathComponent] overWrite:YES];
        [zip UnzipCloseFile];
        if (success) {
            __unsafe_unretained NSString *pathToManifest = [NSString stringWithFormat:@"%@/%@", urlCacheStorePath, @"manifest.afcache"];

            __unsafe_unretained AFPackageInfo *packageInfo;
            __unsafe_unretained NSURL *itemURL = cacheableItem.url;

            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(newPackageInfoByImportingCacheManifestAtPath:intoCacheStoreWithPath:withPackageURL:)]];
            [inv setTarget:self];
            [inv setSelector:@selector(newPackageInfoByImportingCacheManifestAtPath:intoCacheStoreWithPath:withPackageURL:)];

            // if you have arguments, set them up here
            // starting at 2, since 0 is the target and 1 is the selector
            [inv setArgument:&pathToManifest atIndex:2];
            [inv setArgument:&urlCacheStorePath atIndex:3];
            [inv setArgument:&itemURL atIndex:4];

            [inv performSelectorOnMainThread:@selector(invoke) withObject:nil waitUntilDone:YES];

            [inv getReturnValue:&packageInfo];

            // store information about the imported items
            if (preservePackageInfo) {
                [packageInfo.userData addEntriesFromDictionary:userData];
                [self.packageInfos setObject:packageInfo forKey:[cacheableItem.url absoluteString]];
            }
            else {
                NSError *error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:pathToZip error:&error];
            }

            if (((id)cacheableItem.delegate) == self) {
                NSAssert(false, @"you may not assign the AFCache singleton as a delegate.");
            }

            [self performSelectorOnMainThread:@selector(performArchiveReadyWithItem:)
                                   withObject:cacheableItem
                                waitUntilDone:YES];

            [self performSelectorOnMainThread:@selector(archive) withObject:nil waitUntilDone:YES];
            AFLog(@"finished unzipping archive");
        } else {
            AFLog(@"Unzipping failed. Broken archive?");
            [self performSelectorOnMainThread:@selector(performUnarchivingFailedWithItem:)
                                   withObject:cacheableItem
                                waitUntilDone:YES];
        }
	}
}

- (AFPackageInfo*)newPackageInfoByImportingCacheManifestAtPath:(NSString*)manifestPath intoCacheStoreWithPath:(NSString*)urlCacheStorePath withPackageURL:(NSURL*)packageURL {

	NSError *error = nil;
	AFCacheableItemInfo *info = nil;
	NSString *URL = nil;
	NSString *lastModified = nil;
	NSString *expires = nil;
    NSString *mimeType = nil;
    NSString *filename = nil;
	int line = 0;
	
    // create a package info object for this package
	// that enables the cache to keep track of items that have been included in a package
	AFPackageInfo *packageInfo = [[AFPackageInfo alloc] init];
	packageInfo.packageURL = packageURL;

	NSMutableArray *resourceURLs = [[NSMutableArray alloc] init];
	
    //NSString *pathToMetaFolder = [NSString stringWithFormat:@"%@/%@", urlCacheStorePath, @".userdata"];
	NSString *manifest = [NSString stringWithContentsOfFile:manifestPath encoding:NSASCIIStringEncoding error:&error];
	NSArray *entries = [manifest componentsSeparatedByString:@"\n"];
	
	NSMutableDictionary* cacheInfoDictionary = [NSMutableDictionary dictionary];    
	DateParser* dateParser = [[DateParser alloc] init];
	for (NSString *entry in entries) {
		line++;
		if ([entry length] == 0) {
			continue;
		}
		
		NSArray *values = [entry componentsSeparatedByString:@" ; "];
		if ([values count] == 0) continue;
		if ([values count] < 5) {
			NSArray *keyval = [entry componentsSeparatedByString:@" = "];
			if ([keyval count] == 2) {
				NSString *key_ = [keyval objectAtIndex:0];
				NSString *val_ = [keyval objectAtIndex:1];
				if ([@"baseURL" isEqualToString:key_]) {
					packageInfo.baseURL = [NSURL URLWithString:val_];
				}
			} else {
				NSLog(@"Invalid entry in manifest in line %d: %@", line, entry);
			}
			continue;
		}
		info = [[AFCacheableItemInfo alloc] init];		
		
		// parse url
		URL = [values objectAtIndex:ManifestKeyURL];
		
		// parse last-modified
		lastModified = [values objectAtIndex:ManifestKeyLastModified];
		info.lastModified = [dateParser gh_parseHTTP:lastModified];
		
		// parse expires
        expires = [values objectAtIndex:ManifestKeyExpires];
        info.expireDate = [dateParser gh_parseHTTP:expires];
		
		mimeType = [values objectAtIndex:ManifestKeyMimeType];
        
        if( 0 == [mimeType length] || [mimeType isEqualToString:@"NULL"] ) {
            mimeType = nil;
        } else {
            info.mimeType = mimeType;            
        }

		filename = [values objectAtIndex:ManifestKeyFilename];
        if ([filename length] > 0 && ![filename isEqualToString:@"NULL"]) {
            info.filename = filename;
        } else {
            NSLog(@"No filename given for entry in line %d: %@", line, entry);
        }

        uint64_t contentLength = [self setContentLengthForFile:[urlCacheStorePath stringByAppendingPathComponent: filename]];

		info.contentLength = contentLength;

#if MAINTAINER_WARNINGS
#warning BK: textEncodingName always nil here
#endif
        
        info.response = [[NSURLResponse alloc] initWithURL: [NSURL URLWithString: URL]
                                                   MIMEType:mimeType
                                      expectedContentLength: contentLength
                                           textEncodingName: nil];

        [resourceURLs addObject:URL];
		
		[cacheInfoDictionary setObject:info forKey:URL];               
	}
	
	packageInfo.resourceURLs = [NSArray arrayWithArray:resourceURLs];
	
	// import generated cacheInfos in to the AFCache info store
	[self storeCacheInfo:cacheInfoDictionary];
	
	return packageInfo;
}

// TODO: Move to NSFileHandle+AFCache, merge with method #flagAsDownloadStartedWithContentLength:
- (uint64_t)setContentLengthForFile:(NSString*)filename
{
    const char* cfilename = [filename fileSystemRepresentation];

    NSError* err = nil;
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filename error:&err];
    if (err) {
        AFLog(@"Could not get file attributes for %@", filename);
        return 0;
    }
    uint64_t fileSize = [attrs fileSize];
    if (0 != setxattr(cfilename, kAFCacheContentLengthFileAttribute, &fileSize, sizeof(fileSize), 0, 0)) {
        AFLog(@"Could not set content length for file %@", filename);
        return 0;
    }

    return fileSize;
}

- (void)storeCacheInfo:(NSDictionary*)dictionary {
    @synchronized(self) {
        for (NSString* key in dictionary) {
            AFCacheableItemInfo* info = [dictionary objectForKey:key];
            [self.cachedItemInfos setObject:info forKey:key];
        }
    }
}

#pragma mark serialization methods

- (void)performArchiveReadyWithItem:(AFCacheableItem*)cacheableItem
{
    cacheableItem.info.packageArchiveStatus = kAFCachePackageArchiveStatusConsumed;
}

- (void)performUnarchivingFailedWithItem:(AFCacheableItem*)cacheableItem
{
    cacheableItem.info.packageArchiveStatus = kAFCachePackageArchiveStatusUnarchivingFailed;
}

// import and optionally overwrite a cacheableitem. might fail if a download with the very same url is in progress.
- (BOOL)importCacheableItem:(AFCacheableItem*)cacheableItem withData:(NSData*)theData {	
	if (cacheableItem==nil || [self isQueuedOrDownloadingURL:cacheableItem.url]) return NO;
	[cacheableItem setDataAndFile:theData];
	[self.cachedItemInfos setObject:cacheableItem.info forKey:[cacheableItem.url absoluteString]];
	[self archive];
	return YES;
}

- (AFCacheableItem *)importObjectForURL:(NSURL *)url data:(NSData *)data
{
    AFCacheableItem *cachedItem = [self cacheableItemFromCacheStore:url];
    if (cachedItem) {
        return cachedItem;
    }
    else {
        AFCacheableItem *item = [[AFCacheableItem alloc] initWithURL:url lastModified:[NSDate date] expireDate:nil];
        
        [self importCacheableItem:item withData:data];
        
        return item;
    }
}


- (BOOL)importCacheableItem:(AFCacheableItem*)cacheableItem withFile:(NSURL*)fileURL {
    if (cacheableItem==nil || [self isQueuedOrDownloadingURL:cacheableItem.url])
    {
        return NO;
    }
    
    NSString* destinationPath = [self fullPathForCacheableItem:cacheableItem];
    NSString* destinationFolder = [destinationPath stringByDeletingLastPathComponent];
    NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    //ensure directory exists
    NSError * directoryError = nil;
    [fileManager createDirectoryAtPath:destinationFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&directoryError];
    if (directoryError != nil) {
        NSLog(@"error creating directory: %@", directoryError);
        return NO;
    }
    
    //ensure file doesn't exist already
    NSError *cleanupError;
    if ([fileManager fileExistsAtPath:[destinationURL path]])
    {
        [fileManager removeItemAtURL:destinationURL error:&cleanupError];
        if (cleanupError != nil) {
            NSLog(@"error removing file: %@", cleanupError);
            return NO;
        }
    }
    
    //move
    NSError *moveError;
    if ( ![fileManager moveItemAtURL:fileURL
                              toURL:destinationURL
                              error:&moveError] )
    {
        NSLog(@"ERROR importCacheableItem: %@",[moveError description]);
        [fileManager removeItemAtURL:fileURL error:nil];
        return NO;
    }
    
    //mark
    [AFCache addSkipBackupAttributeToItemAtURL:destinationURL];
    [self.cachedItemInfos setObject:cacheableItem.info forKey:[cacheableItem.url absoluteString]];
    [self archive];
    return YES;
}

- (AFCacheableItem *)importObjectForURL:(NSURL *)url byMovingFile:(NSURL *)fileURL
{
    AFCacheableItem *item = [[AFCacheableItem alloc] initWithURL:url lastModified:[NSDate date] expireDate:nil];
    if ([self importCacheableItem:item withFile:fileURL]) {
        return item;
    }
    return nil;
    
}

- (void)purgeCacheableItemForURL:(NSURL*)url {
    if (!url) {
        return;
    }
    AFCacheableItemInfo *cacheableItemInfo = [self.cachedItemInfos valueForKey:[url absoluteString]];
	[self removeCacheEntry:cacheableItemInfo fileOnly:NO fallbackURL:url];
}

- (void)purgePackageArchiveForURL:(NSURL*)url {
	[self purgeCacheableItemForURL:url];
}

- (NSString*)userDataPathForPackageArchiveKey:(NSString*)archiveKey {
	if (archiveKey == nil) {
		return [NSString stringWithFormat:@"%@/%@", self.dataPath, kAFCacheUserDataFolder];
	} else {
		return [NSString stringWithFormat:@"%@/%@/%@", self.dataPath, kAFCacheUserDataFolder, archiveKey];
	}
}

// Return package information for package with urlstring as key
- (AFPackageInfo*)packageInfoForURL:(NSURL*)url {
	NSString *key = [url absoluteString];
	return [self.packageInfos valueForKey:key];
}

#pragma mark -
#pragma mark Deprecated methods

// Deprecated. Use consumePackageArchive:preservePackageInfo: instead
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem {
	[self consumePackageArchive:cacheableItem preservePackageInfo:NO];
}

@end
