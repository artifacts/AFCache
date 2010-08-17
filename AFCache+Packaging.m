//
//  AFCache+Packaging.m
//  AFCache
//
//  Created by Michael Markowski on 13.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCache+PrivateAPI.h"
#import "ZipArchive.h"
#import "DateParser.h"

@implementation AFCache (Packaging)

- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate {
	AFCacheableItem *item = [self cachedObjectForURL: url delegate: aDelegate selector: @selector(packageArchiveDidFinishLoading:) options: 0];
	item.isPackageArchive = YES;
	return item;
}

- (void) packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem {
	if ([cacheableItem.delegate respondsToSelector:@selector(packageArchiveDidFinishLoading:)]) {
		[cacheableItem.delegate performSelector:@selector(packageArchiveDidFinishLoading:) withObject:cacheableItem];
	}	
}

- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem
{
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
    
    NSLog(@"starting to unzip archive");
    
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
	for (NSString *entry in entries) {
        line++;
		if ([entry length] == 0)
        {
            continue;
        }
		
		NSArray *values = [entry componentsSeparatedByString:@" ; "];
		if ([values count] == 0) continue;
		if ([values count] != 3) {
			NSLog(@"Invalid entry in manifest at line %d: %@", line, entry);
			continue;
		}
		info = [[AFCacheableItemInfo alloc] init];		
		lastModified = [values objectAtIndex:ManifestKeyLastModified];
		info.lastModified = [DateParser gh_parseHTTP:lastModified];
		
		expires = [values objectAtIndex:ManifestKeyExpires];
		info.expireDate = [DateParser gh_parseHTTP:expires];
		
		URL = [values objectAtIndex:ManifestKeyURL];
		key = [self filenameForURLString:URL];
		[cacheInfoStore setObject:info forKey:key];
        [self setContentLengthForFile:[urlCacheStorePath stringByAppendingPathComponent:key]];
        
		[info release];		
	}
	[[NSFileManager defaultManager] removeItemAtPath:pathToZip error:&error];
	if (cacheableItem.delegate == self) {
		NSAssert(false, @"you may not assign the AFCache singleton as a delegate.");
	}
    
    [self performSelectorOnMainThread:@selector(performArchiveReadyWithItem:)
                           withObject:cacheableItem
                        waitUntilDone:YES];
	
	[self archive];
    
    NSLog(@"finished unzipping archive");
	
    [pool release];
}

#pragma mark serialization methods

#ifndef AFCACHE_NO_MAINTAINER_WARNINGS
#warning TODO method below maybe obsolete?
#endif

- (BOOL)fillCacheWithArchiveFromURL:(NSURL *)url
{
    NSURLResponse *response = nil;
    NSError *err = nil;
    
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL: url];
    
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                         returningResponse:&response
                                                     error:&err];    
    if (nil != err)
    {
        NSLog(@"Error: %@", err);
        [request release];
        return NO;
    }
    
    if ([response respondsToSelector: @selector(statusCode)]) {
        int statusCode = [( (NSHTTPURLResponse *)response )statusCode];
        if (statusCode != 200 && statusCode != 304) {
            [request release];
            return NO;
        }
    }
    
    NSPropertyListFormat format = 0;
    NSString* error = nil;
    NSDictionary* dict = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:0 format:&format errorDescription:&error];
    
    for (NSString* key in dict)
    {
        NSURL* url = [NSURL URLWithString:key];
        if (nil != [self cachedObjectForURL:url])
        {
            continue;
        }
        AFCacheableItem* item = [[[AFCacheableItem alloc] init] autorelease];
        NSDictionary* itemDict = [dict objectForKey:key];
        
        item.url = url;
        item.mimeType = [itemDict objectForKey:@"mimeType"];
        item.data = [itemDict objectForKey:@"data"];
        item.cache = self;
        
        [self setObject:item forURL:item.url];
    }
	[request release];
    
    return YES;
}

- (void)performArchiveReadyWithItem:(AFCacheableItem*)cacheableItem
{
    [self signalItemsForURL:cacheableItem.url
              usingSelector:@selector(packageArchiveDidFinishExtracting:)];
}

// import and optionally overwrite a cacheableitem. might fail if a download with the very same url is in progress.
- (BOOL)importCacheableItem:(AFCacheableItem*)cacheableItem withData:(NSData*)theData {
	if ([cacheableItem isDownloading]) return NO;
	[cacheableItem setDataAndFile:theData];
	return YES;
}

- (void)purgeCacheableItemForURL:(NSURL*)url {
	NSString *filePath = [self filePathForURL:url];
	[self removeCacheEntryWithFilePath:filePath fileOnly:NO];
}

@end
