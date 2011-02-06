//
//  AFCache+Packaging.m
//  AFCache
//
//  Created by Michael Markowski on 13.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCache+PrivateAPI.h"
#import "AFCacheableItem+Packaging.h"
#import "ZipArchive.h"
#import "DateParser.h"
#import "AFPackageInfo.h"

@implementation AFCache (Packaging)

enum ManifestKeys {
	ManifestKeyURL = 0,
	ManifestKeyLastModified = 1,
	ManifestKeyExpires = 2,
};

- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate {
	AFCacheableItem *item = [self cachedObjectForURL:url
											delegate:aDelegate
											selector:@selector(packageArchiveDidFinishLoading:)
									 didFailSelector:@selector(packageArchiveDidFailLoading:)
											 options:kAFCacheIsPackageArchive | kAFCacheRevalidateEntry
											userData:nil
											username:nil
											password:nil];
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
											password: password];
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
 * The URL as absolute string is used as a key and package information can be accessed via
 * packageInfoForPackageArchiveKey:
 */

- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem preservePackageInfo:(BOOL)preservePackageInfo {
	if (![[clientItems objectForKey:cacheableItem.url] containsObject:cacheableItem]) {
		[self registerItem:cacheableItem];
	}
	
	NSString *urlCacheStorePath = self.dataPath;
	NSString *pathToZip = [NSString stringWithFormat:@"%@/%@", urlCacheStorePath, [cacheableItem filename]];
	
	NSDictionary* arguments = 
	[NSDictionary dictionaryWithObjectsAndKeys:
	 pathToZip,				@"pathToZip",
	 cacheableItem,			@"cacheableItem",
	 urlCacheStorePath,		@"urlCacheStorePath",
	 [NSNumber numberWithBool:preservePackageInfo], @"preservePackageInfo",
	 nil];
	
	[packageArchiveQueue_ addOperation:[[[NSInvocationOperation alloc] initWithTarget:self
																			 selector:@selector(unzipWithArguments:)
																			   object:arguments] autorelease]];
}


- (void)unzipWithArguments:(NSDictionary*)arguments {
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
#ifdef AFCACHE_LOGGING_ENABLED
    NSLog(@"starting to unzip archive");
#endif
    // create a package info object for this package
	// that enables the cache to keep track of items that have been included in a package
	AFPackageInfo *packageInfo = [[AFPackageInfo alloc] init];	
	NSMutableArray *resourceURLs = [[NSMutableArray alloc] init];
	
    // get arguments from dictionary
    NSString* pathToZip				=	[arguments objectForKey:@"pathToZip"];
    AFCacheableItem* cacheableItem	=	[arguments objectForKey:@"cacheableItem"];
    NSString* urlCacheStorePath		=	[arguments objectForKey:@"urlCacheStorePath"];
	BOOL preservePackageInfo		=	[[arguments objectForKey:@"preservePackageInfo"] boolValue];
	
	packageInfo.packageURL = cacheableItem.url;
	
    ZipArchive *zip = [[ZipArchive alloc] init];
    BOOL success = [zip UnzipOpenFile:pathToZip];
	if (success == YES) {
		[zip UnzipFileTo:urlCacheStorePath overWrite:YES];
		[zip UnzipCloseFile];
		[zip release];
		
		NSError *error = nil;
		AFCacheableItemInfo *info = nil;
		NSString *URL = nil;
		NSString *lastModified = nil;
		NSString *expires = nil;
		NSString *key = nil;
		int line = 0;
		
		NSString *pathToManifest = [NSString stringWithFormat:@"%@/%@", urlCacheStorePath, @"manifest.afcache"];
		//NSString *pathToMetaFolder = [NSString stringWithFormat:@"%@/%@", urlCacheStorePath, @".userdata"];
		NSString *manifest = [NSString stringWithContentsOfFile:pathToManifest encoding:NSASCIIStringEncoding error:&error];
		NSArray *entries = [manifest componentsSeparatedByString:@"\n"];
		
		NSMutableDictionary* cacheInfoDictionary = [NSMutableDictionary dictionary];    
		DateParser* dateParser = [[[DateParser alloc] init] autorelease];
		for (NSString *entry in entries) {
			line++;
			if ([entry length] == 0) {
				continue;
			}
			
			NSArray *values = [entry componentsSeparatedByString:@" ; "];
			if ([values count] == 0) continue;
			if ([values count] < 2) {
				NSArray *keyval = [entry componentsSeparatedByString:@" = "];
				if ([keyval count] == 2) {
					NSString *key_ = [keyval objectAtIndex:0];
					NSString *val_ = [keyval objectAtIndex:1];
					if ([@"baseURL" isEqualToString:key_]) {
						packageInfo.baseURL = [NSURL URLWithString:val_];
					}
				} else {
					NSLog(@"Invalid entry in manifest at line %d: %@", line, entry);
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
			if ([values count] > 2) {
				expires = [values objectAtIndex:ManifestKeyExpires];
				info.expireDate = [dateParser gh_parseHTTP:expires];
			}
			
			key = [self filenameForURLString:URL];
			[resourceURLs addObject:URL];
			
			[cacheInfoDictionary setObject:info forKey:key];               
			[self setContentLengthForFile:[urlCacheStorePath stringByAppendingPathComponent:key]];
			
			[info release];		
		}

		// store information about the imported items
		if (preservePackageInfo == YES) {
			[[AFCache sharedInstance].packageInfos setObject:packageInfo forKey:[cacheableItem.url absoluteString]];
		}
		
		//if (removeAfterExtracting == YES) {
		//	[[NSFileManager defaultManager] removeItemAtPath:pathToZip error:&error];
		//}
		
		if (cacheableItem.delegate == self) {
			NSAssert(false, @"you may not assign the AFCache singleton as a delegate.");
		}
		
		[self performSelectorOnMainThread:@selector(storeCacheInfo:)
							   withObject:cacheInfoDictionary
							waitUntilDone:YES];
		
		[self performSelectorOnMainThread:@selector(performArchiveReadyWithItem:)
							   withObject:cacheableItem
							waitUntilDone:YES];
		
		[self performSelectorOnMainThread:@selector(archive) withObject:nil waitUntilDone:YES];
		
#ifdef AFCACHE_LOGGING_ENABLED
		NSLog(@"finished unzipping archive");
#endif
	} else {
		NSLog(@"Unzipping failed. Broken archive?");
		[self performSelectorOnMainThread:@selector(performArchiveReadyWithItem:)
							   withObject:cacheableItem
							waitUntilDone:YES];		
	}

	[packageInfo release];
	[resourceURLs release];	
	[pool release];
	
}

- (void)storeCacheInfo:(NSDictionary*)dictionary {
    @synchronized(self) {
        for (NSString* key in dictionary) {
            AFCacheableItemInfo* info = [dictionary objectForKey:key];
            [cacheInfoStore setObject:info forKey:key];
        }
    }
}

#pragma mark serialization methods

- (void)performArchiveReadyWithItem:(AFCacheableItem*)cacheableItem
{
	[self signalItemsForURL:cacheableItem.url
              usingSelector:@selector(packageArchiveDidFinishExtracting:)];
	[cacheableItem.cache removeItemsForURL:cacheableItem.url]; 
}

- (void)performUnarchivingFailedWithItem:(AFCacheableItem*)cacheableItem
{
	[self signalItemsForURL:cacheableItem.url
              usingSelector:@selector(packageArchiveDidFailExtracting:)];
	[cacheableItem.cache removeItemsForURL:cacheableItem.url]; 
}

// import and optionally overwrite a cacheableitem. might fail if a download with the very same url is in progress.
- (BOOL)importCacheableItem:(AFCacheableItem*)cacheableItem withData:(NSData*)theData {	
	if (cacheableItem==nil || [cacheableItem isDownloading]) return NO;
	[cacheableItem setDataAndFile:theData];
	NSString* key = [self filenameForURL:cacheableItem.url];
	[cacheInfoStore setObject:cacheableItem.info forKey:key];
	[self archive];
	return YES;
}

- (void)purgeCacheableItemForURL:(NSURL*)url {
	NSString *filePath = [self filePathForURL:url];
	[self removeCacheEntryWithFilePath:filePath fileOnly:NO];	
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
	return [packageInfos valueForKey:key];
}

- (void)removePackageInfoForPackageArchiveKey:(NSString*)key {
	[packageInfos removeObjectForKey:key];
	[[AFCache sharedInstance] archive];
}

#pragma mark -
#pragma mark Deprecated methods

// Deprecated. Use consumePackageArchive:preservePackageInfo: instead
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem {
	[self consumePackageArchive:cacheableItem preservePackageInfo:NO];
}


@end
