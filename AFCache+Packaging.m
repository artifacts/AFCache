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

@implementation AFCache (Packaging)

- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate {
	AFCacheableItem *item = [self cachedObjectForURL:url
											delegate:aDelegate
											selector:@selector(packageArchiveDidFinishLoading:)
									 didFailSelector:@selector(packageArchiveDidFailLoading:)
											 options:kAFCacheIsPackageArchive
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
											 options: kAFCacheIsPackageArchive
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

- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem
{
	if (![[clientItems objectForKey:cacheableItem.url] containsObject:cacheableItem])
	{
		[self registerItem:cacheableItem];
	}
	cacheableItem.isUnzipping = YES;
	
	NSString *urlCacheStorePath = self.dataPath;
	NSString *pathToZip = [NSString stringWithFormat:@"%@/%@", urlCacheStorePath, [cacheableItem filename]];
	NSDictionary* arguments = [NSDictionary dictionaryWithObjectsAndKeys:
								   pathToZip, @"pathToZip",
								   cacheableItem, @"cacheableItem",
								   urlCacheStorePath, @"urlCacheStorePath",
								   nil];
		
	[NSThread detachNewThreadSelector:@selector(unzipThreadWithArguments:)
	                             toTarget:self
	                           withObject:arguments];
		
		
		
}

enum ManifestKeys {
	ManifestKeyURL = 0,
	ManifestKeyLastModified = 1,
	ManifestKeyExpires = 2,
};

- (void)unzipThreadWithArguments:(NSDictionary*)arguments
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [NSThread setThreadPriority:0.0];
    
#ifdef AFCACHE_LOGGING_ENABLED
    NSLog(@"starting to unzip archive");
#endif
    
    // get arguments from dictionary
    NSString* pathToZip = [arguments objectForKey:@"pathToZip"];
    AFCacheableItem* cacheableItem = [arguments objectForKey:@"cacheableItem"];
    NSString* urlCacheStorePath = [arguments objectForKey:@"urlCacheStorePath"];
    
    ZipArchive *zip = [[ZipArchive alloc] init];
    [zip UnzipOpenFile:pathToZip];
    [zip UnzipFileTo:urlCacheStorePath overWrite:YES];
    [zip UnzipCloseFile];
    [zip release];

    NSString *pathToManifest = [NSString stringWithFormat:@"%@/%@", urlCacheStorePath, @"manifest.afcache"];
    NSError *error = nil;
    NSString *manifest = [NSString stringWithContentsOfFile:pathToManifest encoding:NSASCIIStringEncoding error:&error];
    NSArray *entries = [manifest componentsSeparatedByString:@"\n"];
    AFCacheableItemInfo *info;
    NSString *URL;
    NSString *lastModified;
    NSString *expires;
    NSString *key;
    int line = 0;
    
    NSMutableDictionary* cacheInfoDictionary = [NSMutableDictionary dictionary];
    
    DateParser* dateParser = [[[DateParser alloc] init] autorelease];
    for (NSString *entry in entries) {
        line++;
        if ([entry length] == 0)
        {
            continue;
        }
        
        NSArray *values = [entry componentsSeparatedByString:@" ; "];
        if ([values count] == 0) continue;
        if ([values count] < 2) {
            NSLog(@"Invalid entry in manifest at line %d: %@", line, entry);
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
        
        [cacheInfoDictionary setObject:info forKey:key];
                
        [self setContentLengthForFile:[urlCacheStorePath stringByAppendingPathComponent:key]];
        
        [info release];		
    }
    
    //			[[NSFileManager defaultManager] removeItemAtPath:pathToZip error:&error];
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
	
	
	[pool release];
	
}



- (void)storeCacheInfo:(NSDictionary*)dictionary
{
    @synchronized(self)
    {
        for (NSString* key in dictionary)
        {
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
	cacheableItem.isUnzipping = NO;
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

@end
