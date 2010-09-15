/*
 *
 * Copyright 2008 Artifacts - Fine Software Development
 * http://www.artifacts.de
 * Author: Michael Markowski (m.markowski@artifacts.de)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import "AFCache+PrivateAPI.h"
#import "AFCache+Mimetypes.h"
#import <Foundation/NSPropertyList.h>
#import "DateParser.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <uuid/uuid.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#include <sys/xattr.h>
#import "ZipArchive.h"
#import "AFRegexString.h"

const char* kAFCacheContentLengthFileAttribute = "de.artifacts.contentLength";
const char* kAFCacheDownloadingFileAttribute = "de.artifacts.downloading";

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;
static NSString *STORE_ARCHIVE_FILENAME = @ "urlcachestore";

@synthesize cacheEnabled, dataPath, cacheInfoStore, pendingConnections, maxItemFileSize, diskCacheDisplacementTresholdSize, suffixToMimeTypeMap;
@synthesize clientItems;
@synthesize runningZipThreads;

#pragma mark init methods

- (id)init {
	self = [super init];
	if (self != nil) {
		[self reinitialize];
		[self initMimeTypes];
	}
	return self;
}

- (int)totalRequestsForSession {
	return requestCounter;
}

- (int)requestsPending {
	return [pendingConnections count];
}

- (void)setDataPath:(NSString*)newDataPath
{
    [dataPath autorelease];
    dataPath = [newDataPath copy];
    [self reinitialize];
}

// The method reinitialize really initializes the cache.
// This is usefull for testing, when you want to, uh, reinitialize
- (void)reinitialize {
	cacheEnabled = YES;
	maxItemFileSize = kAFCacheDefaultMaxFileSize;
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	
    if (nil == dataPath)
    {
        dataPath = [[[paths objectAtIndex: 0] stringByAppendingPathComponent: STORE_ARCHIVE_FILENAME] copy];
    }
	NSString *filename = [dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
	self.clientItems = nil;
	clientItems = [[NSMutableDictionary alloc] init];
    
	NSDictionary *archivedExpireDates = [NSKeyedUnarchiver unarchiveObjectWithFile: filename];
	if (!archivedExpireDates) {
#if AFCACHE_LOGGING_ENABLED		
		NSLog(@ "Created new expires dictionary");
#endif
		self.cacheInfoStore = nil;
		cacheInfoStore = [[NSMutableDictionary alloc] init];
	}
	else {
		self.cacheInfoStore = [NSMutableDictionary dictionaryWithDictionary: archivedExpireDates];
#if AFCACHE_LOGGING_ENABLED
		NSLog(@ "Successfully unarchived expires dictionary");
#endif
	}
	
	self.pendingConnections = nil;
	pendingConnections = [[NSMutableDictionary alloc] init];
	
	self.runningZipThreads = nil;
	runningZipThreads = [[NSMutableDictionary alloc] init];
	
	NSError *error = nil;
	/* check for existence of cache directory */
	if ([[NSFileManager defaultManager] fileExistsAtPath: dataPath]) {
#if AFCACHE_LOGGING_ENABLED
		NSLog(@ "Successfully unarchived cache store");
#endif
	}
	else {
		if (![[NSFileManager defaultManager] createDirectoryAtPath: dataPath
									   withIntermediateDirectories: YES
														attributes: nil
															 error: &error]) {
			NSLog(@ "Failed to create cache directory at path %@: %@", dataPath, [error description]);
		}
	}
	requestCounter = 0;
	_offline = NO;
}

// remove all expired cache entries
// TODO: exchange with a better displacement strategy
- (void)doHousekeeping {
	unsigned long size = [self diskCacheSize];
	if (size < diskCacheDisplacementTresholdSize) return;
	NSDate *now = [NSDate date];
	NSArray *keys = nil;
	NSString *key = nil;
	for (AFCacheableItemInfo *info in [cacheInfoStore allValues]) {
		if (info.expireDate == [now earlierDate:info.expireDate]) {
			keys = [cacheInfoStore allKeysForObject:info];
			if ([keys count] > 0) {
				key = [keys objectAtIndex:0];
				//[self removeObjectForURLString:key fileOnly:NO];
				[self removeCacheEntryWithFilePath:key fileOnly:NO];
			}
		}
	}
}

- (unsigned long)diskCacheSize {
#ifndef AFCACHE_NO_MAINTAINER_WARNINGS
#warning TODO determine diskCacheSize
#endif
	return 0;
	#define MINBLOCK 4096
	NSDictionary				*fattrs;
	NSDirectoryEnumerator		*de;
	unsigned long               size = 0;
	
    de = [[NSFileManager defaultManager]
		  enumeratorAtPath:self.dataPath];
	
    while([de nextObject]) {
		fattrs = [de fileAttributes];
		if (![[fattrs valueForKey:NSFileType]
			  isEqualToString:NSFileTypeDirectory]) {
			size += ((([[fattrs valueForKey:NSFileSize] unsignedIntValue] +
					   MINBLOCK - 1) / MINBLOCK) * MINBLOCK);
		}
    }
	return size;
}

- (void)setContentLengthForFile:(NSString*)filename
{
    const char* cfilename = [filename fileSystemRepresentation];

    NSError* err = nil;
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filename error:&err];
    if (nil != err)
    {
#ifdef AFCACHE_LOGGING_ENABLED
        NSLog(@"Could not get file attributes for %@", filename);
#endif
        return;
    }
    uint64_t fileSize = [attrs fileSize];
    if (0 != setxattr(cfilename,
                      kAFCacheContentLengthFileAttribute,
                      &fileSize,
                      sizeof(fileSize),
                      0, 0))
    {
#ifdef AFCACHE_LOGGING_ENABLED
        NSLog(@"Could not et content length for file %@", filename);
#endif
        return;
    }
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url {
	return [self cachedObjectForURL: url options: 0];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate
{
	
    return [self cachedObjectForURL: url delegate: aDelegate options: 0];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
								options: (int) options
{

	return [self cachedObjectForURL: url
                           delegate: aDelegate
                           selector: @selector(connectionDidFinish:)
					didFailSelector: @selector(connectionDidFailSelector)
                            options: options
                           userData: nil
						   username: nil password: nil];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
							   selector: (SEL) aSelector 
								options: (int) options
{

	return [self cachedObjectForURL: url
                           delegate: aDelegate
                           selector: aSelector
					didFailSelector: @selector(connectionDidFailSelector)
                            options: options
                           userData: nil
						   username: nil password: nil];
}
    

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
							   selector: (SEL) aSelector 
								options: (int) options
                               userData: (id)userData

{
	return [self cachedObjectForURL:url
						   delegate:aDelegate
						   selector:aSelector
					didFailSelector:@selector(connectionDidFailSelector)
							options:options
						   userData:userData
						   username:nil password:nil];
}

/*
 * Performs an asynchroneous request and calls delegate when finished loading
 *
 */

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
							   selector: (SEL) aSelector 
						didFailSelector: (SEL) aFailSelector 
								options: (int) options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword
{
	requestCounter++;
	int invalidateCacheEntry = options & kAFCacheInvalidateEntry;
	
	
	AFCacheableItem *item = nil;
	if (url != nil) {
		NSURL *internalURL = url;
		// try to get object from disk
		if (self.cacheEnabled && invalidateCacheEntry == 0) {
			item = [self cacheableItemFromCacheStore: internalURL];
			item.delegate = aDelegate;
			item.connectionDidFinishSelector = aSelector;
			item.connectionDidFailSelector = aFailSelector;
			item.tag = requestCounter;
            item.userData = userData;
			item.username = aUsername;
			item.password = aPassword;
			
 		}
		
		// object not in cache. Load it from url.
		if (!item) {
			item = [[[AFCacheableItem alloc] init] autorelease];
			item.connectionDidFinishSelector = aSelector;
			item.connectionDidFailSelector = aFailSelector;
			item.cache = self; // calling this particular setter does not increase the retain count to avoid a cyclic reference from a cacheable item to the cache.
			item.delegate = aDelegate;
			item.url = internalURL;
			item.tag = requestCounter;
            item.userData = userData;
			item.username = aUsername;
			item.password = aPassword;
			
			

            NSString* key = [self filenameForURL:internalURL];
            [cacheInfoStore setObject:item.info forKey:key];		

			[self downloadItem:item];
            return item;
		} else {
			// object found in cache.
			// now check if it is fresh enough to serve it from disk.			
			
			// pretend it's fresh when cache is offline
			if ([self isOffline] == YES) {
                // return item and call delegate only if fully loaded
                if (nil != item.data) {
                    [aDelegate performSelector: aSelector withObject: item];
                    return item;				
                }

                if ([aDelegate respondsToSelector:item.connectionDidFailSelector]) {
					[aDelegate performSelector:item.connectionDidFailSelector withObject:item];
				}
				return nil;
			}
			
            // Check if item is fully loaded already
            if (nil == item.data)
            {
                [self downloadItem:item];
                return item;
            }
            
			[self registerItem:item];

			// Item is fresh, so call didLoad selector and return the cached item.
			if ([item isFresh]) {
				item.cacheStatus = kCacheStatusFresh;
				//item.info.responseTimestamp = [NSDate timeIntervalSinceReferenceDate];
				[item performSelector:@selector(connectionDidFinishLoading:) withObject:nil];
#ifdef AFCACHE_LOGGING_ENABLED
				NSLog(@"serving from cache: %@", item.url);
#endif
				return item;
			}
			// Item is not fresh, fire an If-Modified-Since request
			else {
				// save information that object was in cache and has to be revalidated
				item.cacheStatus = kCacheStatusRevalidationPending;
				NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL: internalURL
																		  cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
																	  timeoutInterval: 45];
				NSDate *lastModified = [NSDate dateWithTimeIntervalSinceReferenceDate: [item.info.lastModified timeIntervalSinceReferenceDate]];
				[theRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
				if (item.info.eTag) {
					[theRequest addValue:item.info.eTag forHTTPHeaderField:kHTTPHeaderIfNoneMatch];
				}
				//item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
				NSURLConnection *connection = [NSURLConnection connectionWithRequest: theRequest delegate: item];
				[pendingConnections setObject: connection forKey: internalURL];
			}
			
		}
		return item;
	}
	return nil;
}

#pragma mark synchronous request methods

/*
 * performs a synchroneous request
 *
 */
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
								options: (int) options {
	bool invalidateCacheEntry = options & kAFCacheInvalidateEntry;
	AFCacheableItem *obj = nil;
	if (url != nil) {
		// try to get object from disk if cache is enabled
		if (self.cacheEnabled && !invalidateCacheEntry) {
			obj = [self cacheableItemFromCacheStore: url];
		}
		// Object not in cache. Load it from url.
		if (!obj) {
			NSURLResponse *response = nil;
			NSError *err = nil;
			NSURLRequest *request = [[NSURLRequest alloc] initWithURL: url];
			// The synchronous request will indirectly invoke AFURLCache's
			// storeCachedResponse:forRequest: and add a cacheable item 
			// accordingly.
			NSData *data = [NSURLConnection sendSynchronousRequest: request returningResponse: &response error: &err];
			if ([response respondsToSelector: @selector(statusCode)]) {
				int statusCode = [( (NSHTTPURLResponse *)response )statusCode];
				if (statusCode != 200 && statusCode != 304) {
					[request release];
					return nil;
				}
			}
			// If request was successful there should be a cacheable item now.
			if (data != nil) {
				obj = [self cacheableItemFromCacheStore: url];
			}			
			[request release];
		}
	}
	return obj;
}

#pragma mark file handling methods

- (void)archive {
    @synchronized(self)  // TODO: do we really need a @synchronized here?
    {
        if (requestCounter % kHousekeepingInterval == 0) [self doHousekeeping];
        NSString *filename = [dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
        BOOL result = [NSKeyedArchiver archiveRootObject: cacheInfoStore toFile: filename];
        if (!result) NSLog(@ "Archiving cache failed.");
   }
}

/* removes every file in the cache directory */
- (void)invalidateAll {
	NSError *error;
	
	/* remove the cache directory and its contents */
	if (![[NSFileManager defaultManager] removeItemAtPath: dataPath error: &error]) {
		NSLog(@ "Failed to remove cache contents at path: %@", dataPath);
		return;
	}
	
	/* create a new cache directory */
	if (![[NSFileManager defaultManager] createDirectoryAtPath: dataPath
								   withIntermediateDirectories: NO
													attributes: nil
														 error: &error]) {
		NSLog(@ "Failed to create new cache directory at path: %@", dataPath);
		return;
	}
	self.cacheInfoStore = [NSMutableDictionary dictionary];
}

- (NSString *)filenameForURL: (NSURL *) url {
	return [self filenameForURLString:[url absoluteString]];
}

- (NSString *)filenameForURLString: (NSString *) URLString {
#ifndef AFCACHE_NO_MAINTAINER_WARNINGS
#warning TODO cleanup
#endif
	if ([URLString hasPrefix:@"data:"]) return nil;
	NSString *filepath = [URLString stringByRegex:@".*://" substitution:@""];
	NSString *filepath1 = [filepath stringByRegex:@":[0-9]?*/" substitution:@""];
	NSString *filepath2 = [filepath1 stringByRegex:@"#.*" substitution:@""];
	NSString *filepath3 = [filepath2 stringByRegex:@"\?.*" substitution:@""];	
	NSString *filepath4 = [filepath3 stringByRegex:@"//*" substitution:@"/"];	
	return filepath4;
}

- (NSString *)filePath: (NSString *) filename {
	return [dataPath stringByAppendingPathComponent: filename];
}

- (NSString *)filePathForURL: (NSURL *) url {
	return [dataPath stringByAppendingPathComponent: [self filenameForURL: url]];
}

- (NSDate *)getFileModificationDate: (NSString *) filePath {
	NSError *error;
	/* default date if file doesn't exist (not an error) */
	NSDate *fileDate = [NSDate dateWithTimeIntervalSinceReferenceDate: 0];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
		/* retrieve file attributes */
		NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath: filePath error: &error];
		if (attributes != nil) {
			fileDate = [attributes fileModificationDate];
		}
	}
	return fileDate;
}

- (int)numberOfObjectsInDiskCache {
	if ([[NSFileManager defaultManager] fileExistsAtPath: dataPath]) {
		NSError *err;
		NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: dataPath error:&err];
		return [directoryContents count];
	}
	return 0;
}

- (void)removeCacheEntryWithFilePath:(NSString*)filePath fileOnly:(BOOL) fileOnly {
	NSError *error;
	if ([[NSFileManager defaultManager] removeItemAtPath: filePath error: &error]) {
		if (fileOnly==NO) {
			[cacheInfoStore removeObjectForKey:filePath];
		}
	} else {
		NSLog(@ "Failed to delete outdated cache item %@", filePath);
	}
}

#pragma mark internal core methods

- (void)setObject: (AFCacheableItem *) cacheableItem forURL: (NSURL *) url {
	NSError *error = nil;
//	NSString *key = [self filenameForURL:url];
#ifndef AFCACHE_NO_MAINTAINER_WARNINGS
#warning TODO clean up filenameForURL, filePathForURL methods...
#endif
	NSString *filePath = [self filePathForURL: url];

	/* reset the file's modification date to indicate that the URL has been checked */
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys: [NSDate date], NSFileModificationDate, nil];
	
	if (![[NSFileManager defaultManager] setAttributes: dict ofItemAtPath: filePath error: &error]) {
		NSLog(@ "Failed to reset modification date for cache item %@", filePath);
	}
	[dict release];	
	[self archive];
}

- (NSFileHandle*)createFileForItem:(AFCacheableItem*)cacheableItem
{
    NSError* error = nil;
	NSString *filePath = [self filePathForURL: cacheableItem.url];
	NSFileHandle* fileHandle = nil;
	// remove file if exists
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath] == YES) {
		[self removeCacheEntryWithFilePath:filePath fileOnly:YES];
#ifdef AFCACHE_LOGGING_ENABLED
		NSLog(@"removing %@", filePath);
#endif			
	} 
	
	// create directory if not exists
	NSString *pathToDirectory = [filePath stringByDeletingLastPathComponent];
	if (![[NSFileManager defaultManager] fileExistsAtPath:pathToDirectory] == YES) {
		[[NSFileManager defaultManager] createDirectoryAtPath:pathToDirectory withIntermediateDirectories:YES attributes:nil error:&error];		
#ifdef AFCACHE_LOGGING_ENABLED
		NSLog(@"creating directory %@", pathToDirectory);
#endif			
	}
	
	// write file
	if (cacheableItem.info.contentLength < maxItemFileSize || cacheableItem.isPackageArchive) {
		/* file doesn't exist, so create it */
        [[NSFileManager defaultManager] createFileAtPath: filePath
                                                contents: cacheableItem.data
                                              attributes: nil];
        
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
#ifdef AFCACHE_LOGGING_ENABLED
		NSLog(@"created file at path %@ (%d)", filePath, [fileHandle fileDescriptor]);
#endif			
	}
	else {
		NSLog(@ "AFCache: item %@ \nsize exceeds maxItemFileSize (%f). Won't write file to disk",cacheableItem.url, maxItemFileSize);        
		[cacheInfoStore removeObjectForKey: [self filenameForURL:cacheableItem.url]];
	}

    return fileHandle;
}

// If the file exists on disk we return a new AFCacheableItem for it,
// but it may be only half loaded yet.
- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) URL {
	if ([[URL absoluteString] hasPrefix:@"data:"]) return nil;
	NSString *key = [self filenameForURL:URL];
	// the complete path
	NSString *filePath = [self filePathForURL: URL];
#ifdef AFCACHE_LOGGING_ENABLED
	NSLog(@"checking for file at path %@", filePath);
#endif	
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
		
#ifdef AFCACHE_LOGGING_ENABLED
        NSLog(@"Cache hit for URL: %@", [URL absoluteString]);
#endif
		AFCacheableItemInfo *info = [cacheInfoStore objectForKey: key];
		if (!info) {
#ifdef AFCACHE_LOGGING_ENABLED
			NSLog(@"Cache info store out of sync for url %@: No cache info available for key %@. Removing cached file %@.", [URL absoluteString], key, filePath);
#endif	
			[self removeCacheEntryWithFilePath:filePath fileOnly:YES];
			return nil;
		}
		
		AFCacheableItem *cacheableItem = [[AFCacheableItem alloc] init];
		cacheableItem.cache = self;
		cacheableItem.url = URL;
		cacheableItem.info = info;
		[cacheableItem validateCacheStatus];
		if ([self isOffline]) {
			cacheableItem.loadedFromOfflineCache = YES;
			cacheableItem.cacheStatus = kCacheStatusFresh;
			
		}
		// NSAssert(cacheableItem.info!=nil, @"AFCache internal inconsistency (cacheableItemFromCacheStore): Info must not be nil. This is a software bug.");
		return [cacheableItem autorelease];
	}
#ifdef AFCACHE_LOGGING_ENABLED
	NSLog(@"Cache miss for URL: %@.", [URL absoluteString]);
#endif
    
	return nil;
}

- (void)cancelConnectionsForURL: (NSURL *) url 
{
	NSURLConnection *connection = [pendingConnections objectForKey: url];
#ifdef AFCACHE_LOGGING_ENABLED
	NSLog(@"Cancelling connection for URL: %@", [url absoluteString]);
#endif
	[connection cancel];
	[pendingConnections removeObjectForKey: url];
	[self stopUnzippingForURL:url];
}

- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)aDelegate
{
	[self cancelConnectionsForURL:url];
	[self stopUnzippingForURL:url];
	[self removeItemForURL:url itemDelegate:aDelegate];
	
	[cacheInfoStore removeObjectForKey:[self filenameForURL:url]];
	[self archive];
	
}


- (void)stopUnzippingForURL:(NSURL*)url
{
	NSThread* unZipThread = (NSThread*)[runningZipThreads objectForKey:url];
	if (nil != unZipThread)
	{
		[unZipThread cancel];
		[unZipThread release];
		unZipThread = nil; 
		[runningZipThreads removeObjectForKey:url];
	}
	
}

- (void)removeReferenceToConnection: (NSURLConnection *) connection {
	for (id keyURL in[pendingConnections allKeysForObject : connection]) {
		[pendingConnections removeObjectForKey: keyURL];
	}
}

- (void)registerItem:(AFCacheableItem*)item
{
    NSMutableArray* items = [clientItems objectForKey:item.url];
    if (nil == items)
    {
        items = [NSMutableArray arrayWithObject:item];
        [clientItems setObject:items forKey:item.url];
        return;
    }
    
    [items addObject:item];
}

- (void)signalItemsForURL:(NSURL*)url usingSelector:(SEL)selector
{
    NSArray* items = [[clientItems objectForKey:url] copy];
    for (AFCacheableItem* item in items)
    {
        id delegate = item.delegate;
        if ([delegate respondsToSelector:selector])
        {
            [delegate performSelector:selector withObject:item];
        }
    }
	[items release];
}

- (void)removeItemsForURL:(NSURL*)url
{
 	[clientItems removeObjectForKey:url];
}

- (void)removeItemForURL:(NSURL*)url itemDelegate:(id)itemDelegate
{
	AFCacheableItem* itemToRemove = nil;
	NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
	
	for ( AFCacheableItem* item in clientItemsForURL )
	{
		if ( itemDelegate == item.delegate )
		{
			itemToRemove = item;
			break;
		}
	}
	
	if ( itemToRemove )
	{
		[clientItemsForURL removeObjectIdenticalTo:itemToRemove];
		
		if ( ![clientItemsForURL count] )
		{
			[clientItems removeObjectForKey:url];
		}
	}
}

// Download item if we need to.
- (void)downloadItem:(AFCacheableItem*)item
{
  	[self registerItem:item];

    NSString* filePath = [self filePathForURL:item.url];
	if ([[NSFileManager defaultManager] fileExistsAtPath:filePath])
    {
        // check if we are downloading already
        if (nil != [pendingConnections objectForKey:item.url])
        {
            // don't start another connection
#ifdef AFCACHE_LOGGING_ENABLED
            NSLog(@"We are downloading already. Don't start another connection for %@", item.url);
#endif            
            return;
        }
    }
    
    item.fileHandle = [self createFileForItem:item];

    NSURLRequest *theRequest = [NSURLRequest requestWithURL: item.url
                                                cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
                                            timeoutInterval: 190];
    
    item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
    NSURLConnection *connection = [NSURLConnection connectionWithRequest: theRequest delegate: item];
    [pendingConnections setObject: connection forKey: item.url];
}

- (BOOL)hasCachedItemForURL:(NSURL *)url
{
    AFCacheableItem* item = [self cacheableItemFromCacheStore:url];
    if (nil != item)
    {
        return nil != item.data;
    }
    
    return NO;
}

#pragma mark offline methods

- (void)setOffline:(BOOL)value {
	_offline = value;
}

- (BOOL)isOffline {
	return ![self isConnectedToNetwork] || _offline==YES;
}

/*
 * Returns whether we currently have a working connection
 * Note: This should be done asynchronously, i.e. use
 * SCNetworkReachabilityScheduleWithRunLoop and let it update our information.
 */
- (BOOL)isConnectedToNetwork  {
	// Create zero addy
	struct sockaddr_in zeroAddress;
	bzero( &zeroAddress, sizeof(zeroAddress) );
	zeroAddress.sin_len = sizeof(zeroAddress);
	zeroAddress.sin_family = AF_INET;
	// Recover reachability flags
	SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zeroAddress);
	SCNetworkReachabilityFlags flags;
	BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
	CFRelease(defaultRouteReachability);
	if (!didRetrieveFlags) {
		//NSLog(@"Error. Could not recover network reachability flags\n");
		return 0;
	}
	BOOL isReachable = flags & kSCNetworkFlagsReachable;
	BOOL needsConnection = flags & kSCNetworkFlagsConnectionRequired;
	return (isReachable && !needsConnection) ? YES : NO;
}

#pragma mark singleton methods

+ (AFCache *)sharedInstance {
	@synchronized(self) {
		if (sharedAFCacheInstance == nil) {
			sharedAFCacheInstance = [[self alloc] init];
			sharedAFCacheInstance.diskCacheDisplacementTresholdSize = kDefaultDiskCacheDisplacementTresholdSize;
		}
	}
	return sharedAFCacheInstance;
}

+ (id)allocWithZone: (NSZone *) zone {
	@synchronized(self) {
		if (sharedAFCacheInstance == nil) {
			sharedAFCacheInstance = [super allocWithZone: zone];
			return sharedAFCacheInstance;  // assignment and return on first allocation
		}
	}
	return nil; //on subsequent allocation attempts return nil
}

- (id)copyWithZone: (NSZone *) zone {
	return self;
}

- (id)retain {
	return self;
}

- (NSUInteger)retainCount {
	return UINT_MAX;  //denotes an object that cannot be released
}

- (void)release {
}

- (id)autorelease {
	return self;
}

- (void)dealloc {
	[runningZipThreads performSelector:@selector(cancel)];
	[runningZipThreads removeAllObjects];
	
	self.runningZipThreads = nil;
	
	[suffixToMimeTypeMap release];
	self.pendingConnections = nil;
	self.cacheInfoStore = nil;
	
	[clientItems release];
	[dataPath release];
	
	[super dealloc];
}

@end