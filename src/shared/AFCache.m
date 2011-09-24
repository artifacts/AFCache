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

#import <TargetConditionals.h>

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
#import "AFCache_Logging.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

const char* kAFCacheContentLengthFileAttribute = "de.artifacts.contentLength";
const char* kAFCacheDownloadingFileAttribute = "de.artifacts.downloading";
const double kAFCacheInfiniteFileSize = 0.0;
const double kAFCacheArchiveDelay = 5.0;

extern NSString* const UIApplicationWillResignActiveNotification;

@interface AFCache()
- (void)archiveWithInfoStore:(NSDictionary*)infoStore;
- (void)cancelAllClientItems;
@end

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;

@synthesize cacheEnabled, dataPath, cacheInfoStore, pendingConnections, downloadQueue, maxItemFileSize, diskCacheDisplacementTresholdSize, suffixToMimeTypeMap, networkTimeoutIntervals;
@synthesize clientItems;
@synthesize concurrentConnections;

@synthesize downloadPermission = downloadPermission_;
@synthesize packageInfos;
@synthesize failOnStatusCodeAbove400;

#pragma mark init methods

- (id)init {
	self = [super init];
	if (self != nil) {
#if TARGET_OS_IPHONE
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(resignActive)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
		
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(resignActive)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];        
#endif
		[self reinitialize];
		[self initMimeTypes];
	}
	return self;
}

- (void)resignActive {
    [archiveTimer invalidate];
    [self archiveWithInfoStore:cacheInfoStore];
}

- (int)totalRequestsForSession {
	return requestCounter;
}

- (NSUInteger)requestsPending {
	return [pendingConnections count];
}

- (void)setDataPath:(NSString*)newDataPath {
    if (wantsToArchive_) {
        [archiveTimer invalidate];
        [self archiveWithInfoStore:cacheInfoStore];
        wantsToArchive_ = NO;
    }    
    [dataPath autorelease];
    dataPath = [newDataPath copy];
    double fileSize = self.maxItemFileSize;
    [self reinitialize];
    self.maxItemFileSize = fileSize;
}

// The method reinitialize really initializes the cache.
// This is usefull for testing, when you want to, uh, reinitialize

- (void)reinitialize {
    if (wantsToArchive_) {
        [archiveTimer invalidate];
        [self archiveWithInfoStore:cacheInfoStore];
        wantsToArchive_ = NO;
    }
    [self cancelAllClientItems];
    
	cacheEnabled = YES;
	failOnStatusCodeAbove400 = YES;
	maxItemFileSize = kAFCacheInfiniteFileSize;
	networkTimeoutIntervals.IMSRequest = kDefaultNetworkTimeoutIntervalIMSRequest;
	networkTimeoutIntervals.GETRequest = kDefaultNetworkTimeoutIntervalGETRequest;
	networkTimeoutIntervals.PackageRequest = kDefaultNetworkTimeoutIntervalPackageRequest;
	concurrentConnections = kAFCacheDefaultConcurrentConnections;
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	
    if (nil == dataPath)
    {
        NSString *appId = [[NSBundle mainBundle] bundleIdentifier];
		dataPath = [[[paths objectAtIndex: 0] stringByAppendingPathComponent: appId] copy];
    }
	
	// Deserialize cacheable item info store
	NSString *infoStoreFilename = [dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
	self.clientItems = nil;
	clientItems = [[NSMutableDictionary alloc] init];    
	NSDictionary *archivedExpireDates = [NSKeyedUnarchiver unarchiveObjectWithFile: infoStoreFilename];
	if (!archivedExpireDates) {
		AFLog(@ "Created new expires dictionary");
		self.cacheInfoStore = nil;
		cacheInfoStore = [[NSMutableDictionary alloc] init];
	}
	else {
		self.cacheInfoStore = [NSMutableDictionary dictionaryWithDictionary: archivedExpireDates];
		AFLog(@ "Successfully unarchived expires dictionary");
	}
	archivedExpireDates = nil;
	
	// Deserialize package infos
	NSString *packageInfoPlistFilename = [dataPath stringByAppendingPathComponent: kAFCachePackageInfoDictionaryFilename];
	self.packageInfos = nil;
	NSDictionary *archivedPackageInfos = [NSKeyedUnarchiver unarchiveObjectWithFile: packageInfoPlistFilename];
	
	if (!archivedPackageInfos) {
		AFLog(@ "Created new package infos dictionary");
		packageInfos = [[NSMutableDictionary alloc] init];    
	}
	else {
		self.packageInfos = [NSMutableDictionary dictionaryWithDictionary: archivedPackageInfos];
		AFLog(@ "Successfully unarchived package infos dictionary");
	}
	archivedPackageInfos = nil;
	
	self.pendingConnections = nil;
	pendingConnections = [[NSMutableDictionary alloc] init];
	
	self.downloadQueue = nil;
	downloadQueue = [[NSMutableArray alloc] init];
	
	
	NSError *error = nil;
	/* check for existence of cache directory */
	if ([[NSFileManager defaultManager] fileExistsAtPath: dataPath]) {
		AFLog(@ "Successfully unarchived cache store");
	}
	else {
		if (![[NSFileManager defaultManager] createDirectoryAtPath: dataPath
									   withIntermediateDirectories: YES
														attributes: nil
															 error: &error]) {
			AFLog(@ "Failed to create cache directory at path %@: %@", dataPath, [error description]);
		}
	}
	requestCounter = 0;
	_offline = NO;
    
    [packageArchiveQueue_ release];
    packageArchiveQueue_ = [[NSOperationQueue alloc] init];
    [packageArchiveQueue_ setMaxConcurrentOperationCount:1];
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
#ifdef AFCACHE_MAINTAINER_WARNINGS
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
        AFLog(@"Could not get file attributes for %@", filename);
        return;
    }
    uint64_t fileSize = [attrs fileSize];
    if (0 != setxattr(cfilename,
                      kAFCacheContentLengthFileAttribute,
                      &fileSize,
                      sizeof(fileSize),
                      0, 0))
    {
        AFLog(@"Could not set content length for file %@", filename);
        return;
    }
}

- (AFCacheableItem *)cachedObjectForURLSynchroneous: (NSURL *) url {
	return [self cachedObjectForURLSynchroneous: url options: 0];
}

- (AFCacheableItem *)cachedObjectForURL:(NSURL *)url delegate: (id) aDelegate {
	return [self cachedObjectForURL: url delegate: aDelegate options: 0];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
								options: (int) options
{
	
	return [self cachedObjectForURL: url
                           delegate: aDelegate
                           selector: @selector(connectionDidFinish:)
					didFailSelector: @selector(connectionDidFail:)
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
					didFailSelector: @selector(connectionDidFail:)
                            options: options
                           userData: nil
						   username: nil password: nil];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
							   selector: (SEL) aSelector 
								options: (int) options
                               userData:(id)userData
{
	
	return [self cachedObjectForURL: url
                           delegate: aDelegate
                           selector: aSelector
					didFailSelector: @selector(connectionDidFail:)
                            options: options
                           userData: userData
						   username: nil password: nil];
}


- (AFCacheableItem *)cachedObjectForURL:(NSURL *)url delegate:(id) aDelegate selector:(SEL)aSelector didFailSelector:(SEL)didFailSelector options: (int) options {
	return [self cachedObjectForURL:url delegate:aDelegate selector:aSelector didFailSelector:didFailSelector options:options userData:nil username:nil password:nil];
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
    BOOL invalidateCacheEntry = (options & kAFCacheInvalidateEntry) != 0;
    BOOL revalidateCacheEntry = (options & kAFCacheRevalidateEntry) != 0;
    BOOL neverRevalidate      = (options & kAFCacheNeverRevalidate) != 0;

	AFCacheableItem *item = nil;
	if (url != nil) {
		NSURL *internalURL = url;
		
		// try to get object from disk
		if (self.cacheEnabled && invalidateCacheEntry == 0) {
			item = [self cacheableItemFromCacheStore: internalURL];
			if ([item hasDownloadFileAttribute] || ![item hasValidContentLength])
			{
                if (nil == [pendingConnections objectForKey:internalURL])
				{
					item = nil;
				}
			}
			item.delegate = aDelegate;
			item.connectionDidFinishSelector = aSelector;
			item.connectionDidFailSelector = aFailSelector;
			item.tag = requestCounter;
            item.userData = userData;
			item.username = aUsername;
			item.password = aPassword;
			item.isPackageArchive = (options & kAFCacheIsPackageArchive) != 0;
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
			item.isPackageArchive = (options & kAFCacheIsPackageArchive) != 0;			
			
            NSString* key = [self filenameForURL:internalURL];
            [cacheInfoStore setObject:item.info forKey:key];		
			
			// Register item so that signalling works (even with fresh items 
			// from the cache).
            [self registerItem:item];
			
			[self addItemToDownloadQueue:item];
            return item;
		} else {
			
			// item != nil   here
            // object found in cache.
			// now check if it is fresh enough to serve it from disk.			
			// pretend it's fresh when cache is offline
			if ([self isOffline] && !revalidateCacheEntry) {
                // return item and call delegate only if fully loaded
                if (nil != item.data) {
					if ([aDelegate respondsToSelector:aSelector]) {
						[aDelegate performSelector: aSelector withObject: item];
					}
                    return item;				
                }
				
                if (![item isDownloading])
                {
                    // nobody is downloading, but we got the item from the cachestore.
                    // Something is wrong -> fail
                    if ([aDelegate respondsToSelector:item.connectionDidFailSelector])
                    {
                        [aDelegate performSelector:item.connectionDidFailSelector withObject:item];
                    }
                    return nil;
                }
			}
			
            item.isRevalidating = revalidateCacheEntry;
            
			// Register item so that signalling works (even with fresh items 
			// from the cache).
            [self registerItem:item];
			
            // Check if item is fully loaded already
            if (nil == item.data)
            {
				[self addItemToDownloadQueue:item];
                return item;
            }
            
			// Item is fresh, so call didLoad selector and return the cached item.
			if ([item isFresh] || neverRevalidate) {
				item.cacheStatus = kCacheStatusFresh;
                item.currentContentLength = item.info.contentLength;
				//item.info.responseTimestamp = [NSDate timeIntervalSinceReferenceDate];
				[item performSelector:@selector(connectionDidFinishLoading:) withObject:nil];
				AFLog(@"serving from cache: %@", item.url);
				return item;
			}
			// Item is not fresh, fire an If-Modified-Since request
			else {
                // reset data, because there may be old data set already
                item.data = nil;
                
				// save information that object was in cache and has to be revalidated
				item.cacheStatus = kCacheStatusRevalidationPending;
				NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL: internalURL
																		  cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
																	  timeoutInterval: networkTimeoutIntervals.IMSRequest];
				NSDate *lastModified = [NSDate dateWithTimeIntervalSinceReferenceDate: [item.info.lastModified timeIntervalSinceReferenceDate]];
				[theRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
				if (item.info.eTag) {
					[theRequest addValue:item.info.eTag forHTTPHeaderField:kHTTPHeaderIfNoneMatch];
				}
                
				//item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
				NSURLConnection *connection = [[[NSURLConnection alloc] 
												initWithRequest:theRequest 
												delegate:item
												startImmediately:YES] autorelease];
								
				[pendingConnections setObject: connection forKey: internalURL];
#ifdef AFCACHE_MAINTAINER_WARNINGS
#warning TODO: delegate might be called twice!
				// todo: is this behaviour correct? the item is not nil and will be returned, plus the delegate method is called after revalidation.
				// if the developer calls the delegate by himself if the returned item is not nil, this will lead to a double-call of the delegate which
				// might not be intended
#endif
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

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url options: (int) options {
   return [self cachedObjectForURLSynchroneous:url options:options];
}

- (AFCacheableItem *)cachedObjectForURLSynchroneous: (NSURL *) url 
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
				NSInteger statusCode = [( (NSHTTPURLResponse *)response )statusCode];
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

- (void)archiveWithInfoStore:(NSDictionary*)infoStore {
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
#if AFCACHE_LOGGING_ENABLED
    AFLog(@"start archiving");
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
#endif
    @synchronized(self)
    {
		NSAutoreleasePool* autoreleasePool = [NSAutoreleasePool new];
        if (requestCounter % kHousekeepingInterval == 0) [self doHousekeeping];
        NSString *filename = [dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
        BOOL result = [NSKeyedArchiver archiveRootObject:infoStore toFile: filename]; 
        if (!result) NSLog(@ "Archiving cache failed.");
		
		filename = [dataPath stringByAppendingPathComponent: kAFCachePackageInfoDictionaryFilename];
        result = [NSKeyedArchiver archiveRootObject:packageInfos toFile: filename]; 
        if (!result) NSLog(@ "Archiving package Infos failed.");
		
		[autoreleasePool release], autoreleasePool = nil;
    }
#if AFCACHE_LOGGING_ENABLED
    AFLog(@"Finish archiving in %f", CFAbsoluteTimeGetCurrent() - start);
#endif
    [pool release];
}

- (void)startArchiveThread:(NSTimer*)timer {
    wantsToArchive_ = NO;
    NSDictionary* infoStore = [[cacheInfoStore copy] autorelease];
    [NSThread detachNewThreadSelector:@selector(archiveWithInfoStore:)
                             toTarget:self
                           withObject:infoStore];
}

- (void)archive {
    [archiveTimer invalidate];
    [archiveTimer release];
    archiveTimer = [[NSTimer scheduledTimerWithTimeInterval:kAFCacheArchiveDelay
													 target:self
												   selector:@selector(startArchiveThread:)
												   userInfo:nil
													repeats:NO] retain];
    wantsToArchive_ = YES;
}

/* removes every file in the cache directory */
- (void)invalidateAll {
	NSError *error;
	
	/* remove the cache directory and its contents */
	if (![[NSFileManager defaultManager] removeItemAtPath: dataPath error: &error]) {
		NSLog(@ "Failed to remove cache contents at path: %@", dataPath);
		//return; If there was no old directory we for sure want a new one...
	}
	
	/* create a new cache directory */
	if (![[NSFileManager defaultManager] createDirectoryAtPath: dataPath
								   withIntermediateDirectories: NO
													attributes: nil
														 error: &error]) {
		NSLog(@ "Failed to create new cache directory at path: %@", dataPath);
		return; // this is serious. we need this directory.
	}
	self.cacheInfoStore = [NSMutableDictionary dictionary];
	[[AFCache sharedInstance] archive];
}

- (NSString *)filenameForURL: (NSURL *) url {
	return [self filenameForURLString:[url absoluteString]];
}

- (NSString *)filenameForURLString: (NSString *) URLString {
#ifdef AFCACHE_MAINTAINER_WARNINGS
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

- (NSUInteger)numberOfObjectsInDiskCache {
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
#ifdef AFCACHE_MAINTAINER_WARNINGS
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
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
		[self removeCacheEntryWithFilePath:filePath fileOnly:YES];
		AFLog(@"removing %@", filePath);
	} 
	
	// create directory if not exists
	NSString *pathToDirectory = [filePath stringByDeletingLastPathComponent];
    BOOL isDirectory = YES;
	if (![[NSFileManager defaultManager] fileExistsAtPath:pathToDirectory
                                              isDirectory:&isDirectory]
        || !isDirectory)
    {
        if (!isDirectory)
        {
            if (![[NSFileManager defaultManager] removeItemAtPath:pathToDirectory
															error:&error])
            {
                NSLog(@"AFCache: Could not remove directory \"%@\" (Error: %@)",
                      pathToDirectory,
                      [error localizedDescription]);
            }
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:pathToDirectory withIntermediateDirectories:YES attributes:nil error:&error];		
		AFLog(@"creating directory %@", pathToDirectory);
	}
	
	// write file
	if (maxItemFileSize == kAFCacheInfiniteFileSize || cacheableItem.info.contentLength < maxItemFileSize) {
		/* file doesn't exist, so create it */
        if (![[NSFileManager defaultManager] createFileAtPath: filePath
													 contents: nil
												   attributes: nil])
        {
            NSLog(@"Error: could not create file \"%@\"", filePath);
        }
        
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
		AFLog(@"created file at path %@ (%d)", filePath, [fileHandle fileDescriptor]);	
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
	AFLog(@"checking for file at path %@", filePath);
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: filePath])
    {
        // file doesn't exist. check if someone else is downloading the url already
        if ([[self pendingConnections] objectForKey:URL] != nil
			|| [self isQueuedURL:URL]) 
		{
            AFLog(@"Someone else is already downloading the URL: %@.", [URL absoluteString]);
		}
		else
		{
            AFLog(@"Cache miss for URL: %@.", [URL absoluteString]);
            return nil;
        }
    }
    
    AFLog(@"Cache hit for URL: %@", [URL absoluteString]);

    AFCacheableItemInfo *info = [cacheInfoStore objectForKey: key];
    if (!info) {
		// Something went wrong
        AFLog(@"Cache info store out of sync for url %@: No cache info available for key %@. Removing cached file %@.", [URL absoluteString], key, filePath);
        [self removeCacheEntryWithFilePath:filePath fileOnly:YES];
		
        return nil;
    }
    
    AFCacheableItem *cacheableItem = [[AFCacheableItem alloc] init];
    cacheableItem.cache = self;
    cacheableItem.url = URL;
    cacheableItem.info = info;
    cacheableItem.currentContentLength = info.contentLength;

    [cacheableItem validateCacheStatus];
    if ([self isOffline]) {
        cacheableItem.cacheStatus = kCacheStatusFresh;
        
    }
    // NSAssert(cacheableItem.info!=nil, @"AFCache internal inconsistency (cacheableItemFromCacheStore): Info must not be nil. This is a software bug.");
    return [cacheableItem autorelease];
}

- (void)cancelConnectionsForURL: (NSURL *) url 
{
	if (nil != url)
	{
		NSURLConnection *connection = [pendingConnections objectForKey: url];
		AFLog(@"Cancelling connection for URL: %@", [url absoluteString]);
		[connection cancel];
		[pendingConnections removeObjectForKey: url];
	}
}

- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)aDelegate
{
    if (nil != url)
    {
        [self cancelConnectionsForURL:url];
		
        [self removeItemForURL:url itemDelegate:aDelegate];
        
        [self archive];
    }
}
- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)itemDelegate didLoadSelector:(SEL)selector
{
	if (nil != itemDelegate)
    {
        NSArray *allKeys = [clientItems allKeys];
		for (NSURL *url in allKeys)
        {
            NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
            
            for (AFCacheableItem* item in [[clientItemsForURL copy] autorelease])
            {
                if (itemDelegate == item.delegate &&
					[[url absoluteString] isEqualToString:[item.url absoluteString]] &&
					selector == item.connectionDidFinishSelector)
                {
					[self removeFromDownloadQueue:item];
					item.delegate = nil;
                    [self cancelConnectionsForURL:url];
					
                    [clientItemsForURL removeObjectIdenticalTo:item];
                    
                    if ( ![clientItemsForURL count] )
                    {
                        [clientItems removeObjectForKey:url];
                    }
                }
            }
        }
		
        [self archive];
		[self fillPendingConnections];
    }	
	
}


- (void)cancelAsynchronousOperationsForDelegate:(id)itemDelegate
{
    if (nil != itemDelegate)
    {
        NSArray *allKeys = [clientItems allKeys];
		for (NSURL *url in allKeys)
        {
            NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
            
            for (AFCacheableItem* item in [[clientItemsForURL copy] autorelease])
            {
                if (itemDelegate == item.delegate )
                {
                    [self removeFromDownloadQueue:item];
					item.delegate = nil;
                    [self cancelConnectionsForURL:url];
					
                    [clientItemsForURL removeObjectIdenticalTo:item];
                    
                    if ( ![clientItemsForURL count] )
                    {
                        [clientItems removeObjectForKey:url];
                    }
                }
            }
        }
		
        [self archive];
		[self fillPendingConnections];
    }	
}

- (void)cancelAllClientItems
{
    for (NSURLConnection* connection in [pendingConnections allValues])
    {
        [connection cancel];
    }
    [pendingConnections removeAllObjects];
    
    for (NSArray* items in [clientItems allValues])
    {
        for (AFCacheableItem* item in items)
        {
            item.delegate = nil;
        }
    }
    
    [clientItems removeAllObjects];
}



- (void)removeReferenceToConnection: (NSURLConnection *) connection {
	for (id keyURL in[pendingConnections allKeysForObject : connection]) {
		[pendingConnections removeObjectForKey: keyURL];
	}
}

- (void)registerItem:(AFCacheableItem*)item
{
    NSMutableArray* items = [clientItems objectForKey:item.url];
    if (nil == items) {
        items = [NSMutableArray arrayWithObject:item];
        [clientItems setObject:items forKey:item.url];
        return;
    }
    
	//	ZAssert( 
	//		NSNotFound == [items indexOfObjectIdenticalTo:item],
	//		@"Item added twice." );
	
    [items addObject:item];
}

- (NSArray*)cacheableItemsForURL:(NSURL*)url
{
    return [[[clientItems objectForKey:url] copy] autorelease];
}

- (void)signalItemsForURL:(NSURL*)url usingSelector:(SEL)selector
{
    NSArray* items = [self cacheableItemsForURL:url];
	
    for (AFCacheableItem* item in items)
    {
        id delegate = item.delegate;
        if ([delegate respondsToSelector:selector]) {
            [delegate performSelector:selector withObject:item];
        }
    }
}

- (void)removeItemsForURL:(NSURL*)url {
	[clientItems removeObjectForKey:url];
}


- (void)removeItemForURL:(NSURL*)url itemDelegate:(id)itemDelegate
{
	NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
	// TODO: if there are more delegates on an item, then do not remove the whole item, just set the corrensponding delegate to nil and let the item there for remaining delegates
	for ( AFCacheableItem* item in [[clientItemsForURL copy]autorelease] )
	{
		if ( itemDelegate == item.delegate )
		{
			[self removeFromDownloadQueue:item];
			item.delegate = nil;
            
			[clientItemsForURL removeObjectIdenticalTo:item];
			
			if ( ![clientItemsForURL count] )
			{
				[clientItems removeObjectForKey:url];
			}
		}
	}
	[self fillPendingConnections];
}


// Add the item to the downloadQueue
- (void)addItemToDownloadQueue:(AFCacheableItem*)item
{
    if (!self.downloadPermission)
    {
        if (item.delegate != nil && [item.delegate respondsToSelector:item.connectionDidFailSelector])
        {
            [item.delegate performSelector:item.connectionDidFailSelector withObject:item];
        }
        
        return;
    }
    
	if ((item != nil) && ![item isDownloading])
	{
		[downloadQueue addObject:item];
		if ([[pendingConnections allKeys] count] < concurrentConnections)
		{
			[self downloadItem:item];
		}
	}
}

- (void)removeFromDownloadQueue:(AFCacheableItem*)item
{
	if (item != nil && [downloadQueue containsObject:item])
	{
		// TODO: if there are more delegates on an item, then do not remove the whole item, just set the corrensponding delegate to nil and let the item there for remaining delegates
		[downloadQueue removeObject:item];
	}
}

- (void)removeFromDownloadQueueAndLoadNext:(AFCacheableItem*)item
{
	[self removeFromDownloadQueue:item];
	[self downloadNextEnqueuedItem];
}

- (void)flushDownloadQueue
{
	for (AFCacheableItem *item in [[downloadQueue copy] autorelease])
	{
		[self downloadNextEnqueuedItem];
	}
}

- (void)fillPendingConnections
{
	for (int i = 0; i < concurrentConnections; i++)
	{
		if ([[pendingConnections allKeys] count] < concurrentConnections)
		{
			[self downloadNextEnqueuedItem];
		}
	}
}

- (void)downloadNextEnqueuedItem
{
	if ([downloadQueue count] > 0)
	{
		AFCacheableItem *nextItem = [downloadQueue objectAtIndex:0];
		[self downloadItem:nextItem];
	}
}

- (BOOL)isQueuedURL:(NSURL*)url
{
	
	for (AFCacheableItem *item in downloadQueue)
	{
		if ([[url absoluteString] isEqualToString:[item.url absoluteString]])
		{
			return YES;
		}
	}
	
	return NO;
}



// Download item if we need to.
- (void)downloadItem:(AFCacheableItem*)item
{
    // Remove the item from the queue, becaue we are going to download the item now
    [downloadQueue removeObject:item];
    
    // check if we are downloading already
    if (nil != [pendingConnections objectForKey:item.url])
    {
        // don't start another connection
        AFLog(@"We are downloading already. Won't start another connection for %@", item.url);
        return;
    }
    
	NSTimeInterval timeout = (item.isPackageArchive == YES)
		?networkTimeoutIntervals.PackageRequest
		:networkTimeoutIntervals.GETRequest;
	
    NSURLRequest *theRequest = [NSURLRequest requestWithURL: item.url
                                                cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
                                            timeoutInterval: timeout];
    
    item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
    NSURLConnection *connection = [[[NSURLConnection alloc] 
                                    initWithRequest:theRequest
                                    delegate:item 
                                    startImmediately:YES] autorelease];
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
	return ![self isConnectedToNetwork] || _offline==YES || !self.downloadPermission;
}

/*
 * Returns whether we currently have a working connection
 * Note: This should be done asynchronously, i.e. use
 * SCNetworkReachabilityScheduleWithRunLoop and let it update our information.
 */
- (BOOL)isConnectedToNetwork  {
	// Create zero address
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
			sharedAFCacheInstance.downloadPermission = YES;
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
	[archiveTimer release];
	[suffixToMimeTypeMap release];
	self.pendingConnections = nil;
	self.downloadQueue = nil;
	self.cacheInfoStore = nil;
	
	[clientItems release];
	[dataPath release];
	[packageInfos release];
	
	[super dealloc];
}

@end

#ifdef USE_ENGINEROOM
#import <EngineRoom/logpoints.m>
#endif

@implementation AFCache( LoggingSupport ) 

+ (void) setLoggingEnabled: (BOOL) enabled
{
#ifdef USE_ENGINEROOM
	if( enabled ) {
		ER_ADDRESS_OF_GLOBAL_OR_EMBEDDED( logPointEnableSimple )("AFCache");
	} else {
		ER_ADDRESS_OF_GLOBAL_OR_EMBEDDED( logPointDisableSimple )("AFCache");
	}

	lpkdebugf("AFCache", "using %s", ER_ADDRESS_OF_GLOBAL_OR_EMBEDDED( logPointLibraryIdentifier )() );
	
#else
	AFLog(@"AFCache setLoggingEnabled: ignored (EngineRoom not embedded)"); 
#endif
}

+ (void) setLogFormat: (NSString *) logFormat
{
#ifdef USE_ENGINEROOM
	if( NULL == logPointSetLogFormat ) {
		ER_ADDRESS_OF_GLOBAL_OR_EMBEDDED( logPointSetLogFormat )( [logFormat UTF8String] );
	} else {
		lpkdebugf("AFCache", "%s", "ignored (using non-embedded EngineRoom)"); 		
	}
#else
	AFLog(@"AFCache setLogFormat: ignored (EngineRoom not embedded)"); 
#endif	
}

@end
