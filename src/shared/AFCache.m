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
#import "AFHTTPURLProtocol.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <uuid/uuid.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#include <sys/xattr.h>
#import "AFRegexString.h"
#import "AFCache_Logging.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#if USE_ASSERTS
#define ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(url) NSAssert( [(url) isFileURL] || [self isOffline] == NO, @"No connection should be opened if we're in offline mode - this seems like a bug")
#else
#define ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(url) do{}while(0)
#endif


const char* kAFCacheContentLengthFileAttribute = "de.artifacts.contentLength";
const char* kAFCacheDownloadingFileAttribute = "de.artifacts.downloading";
const double kAFCacheInfiniteFileSize = 0.0;
const double kAFCacheArchiveDelay = 30.0; // archive every 30s


extern NSString* const UIApplicationWillResignActiveNotification;

@interface AFCache()
- (void)archiveWithInfoStore:(NSDictionary*)infoStore;
- (void)cancelAllClientItems;
- (id)initWithContext:(NSString*)context;
@end

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;
static NSMutableDictionary* AFCache_contextCache = nil;

@synthesize cacheEnabled, dataPath, cacheInfoStore, pendingConnections, maxItemFileSize, diskCacheDisplacementTresholdSize, suffixToMimeTypeMap, networkTimeoutIntervals;
@synthesize clientItems;
@synthesize concurrentConnections;
@synthesize pauseDownload = pauseDownload_;
@synthesize downloadPermission = downloadPermission_;
@synthesize packageInfos;
@synthesize failOnStatusCodeAbove400;
//@synthesize cacheWithoutUrlParameter;
//@synthesize cacheWithoutHostname;
//@synthesize userAgent;
//@synthesize disableSSLCertificateValidation;
//@synthesize cacheWithHashname;
@dynamic isConnectedToNetwork;

#pragma mark singleton methods

+ (AFCache *)sharedInstance {
    @synchronized(self) {
        if (sharedAFCacheInstance == nil) {
            sharedAFCacheInstance = [[self alloc] initWithContext:nil];
            sharedAFCacheInstance.diskCacheDisplacementTresholdSize = kDefaultDiskCacheDisplacementTresholdSize;
        }
    }
    return sharedAFCacheInstance;
}

#pragma mark init methods

- (id)initWithContext:(NSString*)context {
    if (nil == context && sharedAFCacheInstance != nil)
    {
        return [AFCache sharedInstance];
    }
    
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
        if (nil == AFCache_contextCache)
        {
            AFCache_contextCache = [[NSMutableDictionary alloc] init];
        }
        
        if (nil != context)
        {
            [AFCache_contextCache setObject:[NSValue valueWithPointer:(__bridge const void *)(self)] forKey:context];
        }
        
        context_ = [context copy];
        isInstancedCache_ = (context != nil);
        self.downloadPermission = YES;
        [self reinitialize];
		[self initMimeTypes];
	}
	return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (nil != context_)
    {
        [AFCache_contextCache removeObjectForKey:context_];
    }

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
    if (isInstancedCache_ && nil != dataPath)
    {
        NSLog(@"Error: Can't change data path on instanced AFCache");
        NSAssert(NO, @"Can't change data path on instanced AFCache");
        return;
    }
    if (wantsToArchive_) {
        [archiveTimer invalidate];
        [self archiveWithInfoStore:cacheInfoStore];
        wantsToArchive_ = NO;
    }
    dataPath = [newDataPath copy];
    double fileSize = self.maxItemFileSize;
    [self reinitialize];
    self.maxItemFileSize = fileSize;
}

- (NSMutableDictionary*)_newCacheInfoStore {
    NSMutableDictionary *aCacheInfoStore = [[NSMutableDictionary alloc] init];
    [aCacheInfoStore setValue:[NSMutableDictionary dictionary] forKey:kAFCacheInfoStoreCachedObjectsKey];
    [aCacheInfoStore setValue:[NSMutableDictionary dictionary] forKey:kAFCacheInfoStoreRedirectsKey];
    return aCacheInfoStore;
}

+ (AFCache*)cacheForContext:(NSString *)context
{
    if (nil == AFCache_contextCache)
    {
        AFCache_contextCache = [[NSMutableDictionary alloc] init];
    }
    
    if (nil == context)
    {
        return [self sharedInstance];
    }
    
    AFCache* cache = [[AFCache_contextCache objectForKey:context] pointerValue];
    if (nil == cache)
    {
        cache = [[[self class] alloc] initWithContext:context];
    }
    
    return cache;
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
    
    _archiveInterval = kAFCacheArchiveDelay;
	cacheEnabled = YES;
	failOnStatusCodeAbove400 = YES;
    self.cacheWithHashname = YES;
	maxItemFileSize = kAFCacheInfiniteFileSize;
	networkTimeoutIntervals.IMSRequest = kDefaultNetworkTimeoutIntervalIMSRequest;
	networkTimeoutIntervals.GETRequest = kDefaultNetworkTimeoutIntervalGETRequest;
	networkTimeoutIntervals.PackageRequest = kDefaultNetworkTimeoutIntervalPackageRequest;
	concurrentConnections = kAFCacheDefaultConcurrentConnections;
	
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    
    if (nil == dataPath)
    {
        NSString *appId = [@"afcache" stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
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
        cacheInfoStore = [self _newCacheInfoStore];
	}
	else {
		self.cacheInfoStore = [NSMutableDictionary dictionaryWithDictionary: archivedExpireDates];
        if ([self.cacheInfoStore valueForKey:kAFCacheInfoStoreCachedObjectsKey] == nil) {
            //NSDictionary *allObjects = [NSDictionary dictionaryWithDictionary:self.cacheInfoStore];
            [self.cacheInfoStore removeAllObjects];
            [cacheInfoStore setValue:[NSMutableDictionary dictionary] forKey:kAFCacheInfoStoreCachedObjectsKey];
            [cacheInfoStore setValue:[NSMutableDictionary dictionary] forKey:kAFCacheInfoStoreRedirectsKey];
			//            [[cacheInfoStore valueForKey:kAFCacheInfoStoreCachedObjectsKey] addEntriesFromDictionary:allObjects];
            AFLog(@ "Changed expires dictionary to new format. All cache entries have been removed.");
        }
		AFLog(@ "Successfully unarchived expires dictionary");
	}

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

	self.pendingConnections = nil;
	pendingConnections = [[NSMutableDictionary alloc] init];
	
	//releases downloadQueue if it is not nil
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
    
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1 || TARGET_OS_MAC && MAC_OS_X_VERSION_MIN_ALLOWED < MAC_OS_X_VERSION_10_8
    [self addSkipBackupAttributeToItemAtURL:[NSURL fileURLWithPath:dataPath]];
#endif
    
	requestCounter = 0;
	_offline = NO;
    
    packageArchiveQueue_ = [[NSOperationQueue alloc] init];
    [packageArchiveQueue_ setMaxConcurrentOperationCount:1];
}

#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1 || TARGET_OS_MAC && MAC_OS_X_VERSION_MIN_ALLOWED < MAC_OS_X_VERSION_10_8
- (BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)URL
{
	assert([[NSFileManager defaultManager] fileExistsAtPath: [URL path]]);
    
    NSError *error = nil;
	
    BOOL success = [URL setResourceValue:[NSNumber numberWithBool:YES] forKey: NSURLIsExcludedFromBackupKey error:&error];
    
    if (!success) {
        NSLog(@"Error excluding %@ from backup %@", [URL lastPathComponent], error);
    }
	return success;
}
#endif
-(void)addRedirectFromURL:(NSURL*)originalURL toURL:(NSURL*)redirectURL
{
	[[self CACHED_REDIRECTS] setObject:[redirectURL absoluteString] forKey:[originalURL absoluteString]];
}

-(void)addRedirectFromURLString:(NSString*)originalURLString toURLString:(NSString*)redirectURLString
{
	[[self CACHED_REDIRECTS] setObject:redirectURLString forKey:originalURLString];
}
// remove all expired cache entries
// TODO: exchange with a better displacement strategy
- (void)doHousekeeping {
    if ([self isOffline]) return; // don't cleanup if we're offline
	unsigned long size = [self diskCacheSize];
	if (size < diskCacheDisplacementTresholdSize) return;
	NSDate *now = [NSDate date];
	NSArray *keys = nil;
	NSString *key = nil;
	for (AFCacheableItemInfo *info in [[self CACHED_OBJECTS] allValues]) {
		if (info.expireDate != nil && info.expireDate == [now earlierDate:info.expireDate]) {
			keys = [[self CACHED_OBJECTS] allKeysForObject:info];
			if ([keys count] > 0) {
				key = [keys objectAtIndex:0];
				[self removeCacheEntry:info fileOnly:NO];
                NSString* fullPath = [[self dataPath] stringByAppendingPathComponent:key];
				[self removeCacheEntryWithFilePath:fullPath fileOnly:NO];
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

- (uint64_t)setContentLengthForFile:(NSString*)filename
{
    const char* cfilename = [filename fileSystemRepresentation];
	
    NSError* err = nil;
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filename error:&err];
    if (nil != err)
    {
        AFLog(@"Could not get file attributes for %@", filename);
        return 0;
    }
    uint64_t fileSize = [attrs fileSize];
    if (0 != setxattr(cfilename,
                      kAFCacheContentLengthFileAttribute,
                      &fileSize,
                      sizeof(fileSize),
                      0, 0))
    {
        AFLog(@"Could not set content length for file %@", filename);
        return 0;
    }
	
    return fileSize;
}

- (NSMutableDictionary*) CACHED_OBJECTS {
    return [cacheInfoStore valueForKey:kAFCacheInfoStoreCachedObjectsKey];
}

- (NSMutableDictionary*) CACHED_REDIRECTS {
    return [cacheInfoStore valueForKey:kAFCacheInfoStoreRedirectsKey];
}

- (AFCacheableItem *)cachedObjectForURLSynchroneous: (NSURL *) url {
	return [self cachedObjectForURLSynchroneous: url options: 0];
}


- (AFCacheableItem *)cachedObjectForURL:(NSURL *)url delegate: (id) aDelegate {
	return [self cachedObjectForURL: url delegate: aDelegate options: 0];
}

- (AFCacheableItem *)cachedObjectForRequest:(NSURLRequest *)aRequest delegate: (id) aDelegate {
	return [self cachedObjectForURL: aRequest.URL
                           delegate: aDelegate
                           selector: @selector(connectionDidFinish:)
					didFailSelector: @selector(connectionDidFail:)
                            options: 0
                           userData: nil
						   username: nil password: nil request:aRequest];
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
						   username: nil password: nil request:nil];
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
						   username: nil password: nil request:nil];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
							   delegate: (id) aDelegate
                               selector: (SEL) aSelector
								options: (int) options
							   userData: (id)userData
{
	return [self cachedObjectForURL: url
                           delegate: aDelegate
                           selector: aSelector
					didFailSelector: @selector(connectionDidFail:)
                            options: options
                           userData: userData
						   username: nil password: nil request:nil];
}


- (AFCacheableItem *)cachedObjectForURL:(NSURL *)url delegate:(id) aDelegate selector:(SEL)aSelector didFailSelector:(SEL)didFailSelector options: (int) options {
	return [self cachedObjectForURL:url delegate:aDelegate selector:aSelector didFailSelector:didFailSelector options:options userData:nil username:nil password:nil request:nil];
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
                                request: (NSURLRequest*)aRequest
{
    return [self cachedObjectForURL:url
                           delegate:aDelegate
                           selector:aSelector
                    didFailSelector:aFailSelector
                    completionBlock:nil
                          failBlock:nil
                      progressBlock:nil
                            options:options
                           userData:userData
                           username:aUsername
                           password:aPassword
                            request:aRequest];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                               delegate: (id)aDelegate
							   selector: (SEL)aSelector
						didFailSelector: (SEL)aFailSelector
                        completionBlock: (id)aCompletionBlock
                              failBlock: (id)aFailBlock
                          progressBlock: (id)aProgressBlock
								options: (int)options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword
                                request: (NSURLRequest*)aRequest
{
	//validate URL and handle invalid url
    if (url == nil || [[url absoluteString] length] == 0)
    {
        NSError *error = [NSError errorWithDomain:@"URL is not set" code:-1 userInfo:nil];
        AFCacheableItem *item = [[AFCacheableItem alloc] init];
        item.error = error;
        [aDelegate performSelector:aFailSelector withObject:item];
#if NS_BLOCKS_AVAILABLE
        AFCacheableItemBlock block = (AFCacheableItemBlock)aFailBlock;
        if (block) block(item);
#endif
        return nil;
    }
    
	requestCounter++;
    BOOL invalidateCacheEntry = (options & kAFCacheInvalidateEntry) != 0;
    BOOL revalidateCacheEntry = (options & kAFCacheRevalidateEntry) != 0;
    BOOL neverRevalidate      = (options & kAFCacheNeverRevalidate) != 0;
    BOOL justFetchHTTPHeader  = (options & kAFCacheJustFetchHTTPHeader) != 0;
    BOOL shouldIgnoreQueue    = (options & kAFCacheIgnoreDownloadQueue) != 0;
    
	AFCacheableItem *item = nil;
    BOOL didRewriteURL = NO; // the request URL might be rewritten by the cache internally if we're offline because the
	// redirect mechanisms in the URL loading system / UIWebView do not seem to work well when
	// no network connection is available.
    
	if (url != nil) {
		NSURL *internalURL = url;
        
        if ([self isOffline] == YES) {
            // We're offline. In this case, we lookup if we have a cached redirect
            // and change the origin URL to the redirected Location.
            NSURL *redirectURL = [self valueForKey:[url absoluteString]];
            if (redirectURL) {
                internalURL = redirectURL;
                didRewriteURL = YES;
            }
        }
		
		// try to get object from disk
		if (self.cacheEnabled && invalidateCacheEntry == 0) {
			item = [self cacheableItemFromCacheStore: internalURL];
			
			
            if (!internalURL.isFileURL && [self isOffline] && !item) {
                // check if there is a cached redirect for this URL, but ONLY if we're offline
                // AFAIU redirects of type 302 MUST NOT be cached
                // since we do not distinguish between 301 and 302 or other types of redirects, nor save the status code anywhere
                // we simply only check the cached redirects if we're offline
                // see http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html 13.4 Response Cacheability
                internalURL = [NSURL URLWithString:[[self CACHED_REDIRECTS] valueForKey:[url absoluteString]]];
                item = [self cacheableItemFromCacheStore: internalURL];
            }
			
            // check validity of cached item
            if (![item isDataLoaded] &&//TODO: validate this check (does this ensure that we continue downloading but also detect corrupt files?)
                ([item hasDownloadFileAttribute] || ![item hasValidContentLength])) {
				
                if (nil == [pendingConnections objectForKey:internalURL])
				{
					//item is not vailid and not allready being downloaded, set item to nil to trigger download
					item = nil;
				}
			}
 		}
        
        BOOL performGETRequest = NO; // will be set to YES if we're online and have a cache miss
        
		if (!item) {
            // we're offline and do not have a cached version, so return nil
            if (!internalURL.isFileURL && [self isOffline])
            {
                if(aFailBlock != nil)
                {
                    ((AFCacheableItemBlock)aFailBlock)(nil);
                }
                return nil;
            }
            
            // we're online - create a new item, since we had a cache miss
            item = [[AFCacheableItem alloc] init];
            performGETRequest = YES;
        }
        
        // setup item
        item.delegate = aDelegate;
        item.connectionDidFinishSelector = aSelector;
        item.connectionDidFailSelector = aFailSelector;
        item.tag = requestCounter;
        item.cache = self; // calling this particular setter does not increase the retain count to avoid a cyclic reference from a cacheable item to the cache.
        item.url = internalURL;
        item.userData = userData;
        item.username = aUsername;
        item.password = aPassword;
		item.justFetchHTTPHeader = justFetchHTTPHeader;
        item.isPackageArchive = (options & kAFCacheIsPackageArchive) != 0;
        item.URLInternallyRewritten = didRewriteURL;
        item.servedFromCache = performGETRequest ? NO : YES;//!performGETRequest
        item.info.request = aRequest;
        
        if (self.cacheWithHashname == NO)
        {
            item.info.filename = [self filenameForURL:item.url];
        }
        
#if NS_BLOCKS_AVAILABLE
        if (aCompletionBlock != nil) {
            item.completionBlock = aCompletionBlock;
        }
        if (aFailBlock != nil) {
            item.failBlock = aFailBlock;
        }
        if (aProgressBlock != nil) {
            item.progressBlock = aProgressBlock;
        }
#endif
		
		if (performGETRequest) {
            // perform a request for our newly created item
            [[self CACHED_OBJECTS] setObject:item.info forKey:[internalURL absoluteString]];
            // Register item so that signalling works (even with fresh items
            // from the cache).
            [self registerClientItem:item];
            [self handleDownloadItem:item ignoreQueue:shouldIgnoreQueue];
            return item;
		}
		else
		{
            // object found in cache.
            // now check if it is fresh enough to serve it from disk.
            // pretend it's fresh when cache is offline
			item.servedFromCache = YES;
            if ([self isOffline] && !revalidateCacheEntry) {
                // return item and call delegate only if fully loaded
                if (nil != item.data) {
                    [item performSelector:@selector(signalItemsDidFinish:)
                               withObject:[NSArray arrayWithObject:item]
                               afterDelay:0.0];
                    return item;
                }
                
                if (![item isDownloading])
                {
                    if ([item hasValidContentLength] && !item.canMapData)
                    {
                        // Perhaps the item just can not be mapped.
                        
                        [item performSelector:@selector(signalItemsDidFinish:)
                                   withObject:[NSArray arrayWithObject:item]
                                   afterDelay:0.0];
                        
                        return item;
                    }
                    
                    // nobody is downloading, but we got the item from the cachestore.
                    // Something is wrong -> fail
                    [item performSelector:@selector(signalItemsDidFail:)
                               withObject:[NSArray arrayWithObject:item]
                               afterDelay:0.0];
                    
                    return nil;
                }
            }
            
            item.isRevalidating = revalidateCacheEntry;
            
            // Register item so that signalling works (even with fresh items
            // from the cache).
            [self registerClientItem:item];
            
            // Check if item is fully loaded already
            if (item.canMapData && nil == item.data && ![item hasValidContentLength])
            {
                [self handleDownloadItem:item ignoreQueue:shouldIgnoreQueue];
                return item;
            }
            
            // Item is fresh, so call didLoad selector and return the cached item.
            if ([item isFresh] || neverRevalidate)
            {
                
                item.cacheStatus = kCacheStatusFresh;
#ifdef RESUMEABLE_DOWNLOAD
				if(item.currentContentLength < item.info.contentLength)
				{
					//resume download
					item.cacheStatus = kCacheStatusDownloading;
                    [self handleDownloadItem:item ignoreQueue:shouldIgnoreQueue];
				}
#else
				item.currentContentLength = item.info.contentLength;
				[item performSelector:@selector(connectionDidFinishLoading:) withObject:nil];
                AFLog(@"serving from cache: %@", item.url);
				
#endif
                return item;
                //item.info.responseTimestamp = [NSDate timeIntervalSinceReferenceDate];
			}
            // Item is not fresh, fire an If-Modified-Since request
            else
            {
				//#ifndef RESUMEABLE_DOWNLOAD
                // reset data, because there may be old data set already
                item.data = nil;//will cause the data to be relaoded from file when accessed next time
				//#endif
                
                // save information that object was in cache and has to be revalidated
                item.cacheStatus = kCacheStatusRevalidationPending;
                NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL: internalURL
                                                                          cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
                                                                      timeoutInterval: networkTimeoutIntervals.IMSRequest];
                NSDate *lastModified = [NSDate dateWithTimeIntervalSinceReferenceDate: [item.info.lastModified timeIntervalSinceReferenceDate]];
                [theRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
                [theRequest setValue:@"" forHTTPHeaderField:AFCacheInternalRequestHeader];
				
                if (item.info.eTag)
                {
                    [theRequest addValue:item.info.eTag forHTTPHeaderField:kHTTPHeaderIfNoneMatch];
                }
                else
                {
                    NSDate *lastModified = [NSDate dateWithTimeIntervalSinceReferenceDate:
                                            [item.info.lastModified timeIntervalSinceReferenceDate]];
                    [theRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
                }
                item.IMSRequest = theRequest;
                ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(theRequest.URL);
                
                [self handleDownloadItem:item ignoreQueue:shouldIgnoreQueue];
                
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
	
#if MAINTAINER_WARNINGS
	//#warning BK: this is in support of using file urls with ste-engine - no info yet for shortCircuiting
#endif
    if( [url isFileURL] ) {
        AFCacheableItem *shortCircuitItem = [[AFCacheableItem alloc] init];
        shortCircuitItem.data = [NSData dataWithContentsOfURL: url];
        return shortCircuitItem;
    }
	
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
            
            ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(url);
            
			NSData *data = [NSURLConnection sendSynchronousRequest: request returningResponse: &response error: &err];
			if ([response respondsToSelector: @selector(statusCode)]) {
				NSInteger statusCode = [( (NSHTTPURLResponse *)response )statusCode];
				if (statusCode != 200 && statusCode != 304) {
					return nil;
				}
			}
			// If request was successful there should be a cacheable item now.
			if (data != nil) {
				obj = [self cacheableItemFromCacheStore: url];
			}
		}
	}
	return obj;
}

#pragma mark file handling methods

- (void)archiveWithInfoStore:(NSDictionary*)infoStore {
    @autoreleasepool {
#if AFCACHE_LOGGING_ENABLED
		AFLog(@"start archiving");
		CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
#endif
        @synchronized(self)
        {
            @autoreleasepool {
                
                if (requestCounter % kHousekeepingInterval == 0) [self doHousekeeping];
                NSString *filename = [dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
                NSData* serializedData = [NSKeyedArchiver archivedDataWithRootObject:infoStore];
                if (serializedData)
                {
                    NSError* error = nil;
                    if (![serializedData writeToFile:filename options:NSDataWritingAtomic error:&error])
                    {
                        NSLog(@"Error: Could not write infoStore to file '%@': Error = %@, infoStore = %@", filename, error, infoStore);
                    }
                }
                else
                {
                    NSLog(@"Error: Could not archive info store: infoStore = %@", infoStore);
                }
                
                filename = [dataPath stringByAppendingPathComponent: kAFCachePackageInfoDictionaryFilename];
                serializedData = [NSKeyedArchiver archivedDataWithRootObject:packageInfos];
                if (serializedData)
                {
                    NSError* error = nil;
                    if (![serializedData writeToFile:filename options:NSDataWritingAtomic error:&error])
                    {
                        NSLog(@"Error: Could not write package infos to file '%@': Error = %@, infoStore = %@", filename, error, packageInfos);
                    }
                }
                else
                {
                    NSLog(@"Error: Could not package infos: %@", packageInfos);
                }
            }
        }
#if AFCACHE_LOGGING_ENABLED
		AFLog(@"Finish archiving in %f", CFAbsoluteTimeGetCurrent() - start);
#endif
    }
}

- (void)startArchiveThread:(NSTimer*)timer {
    wantsToArchive_ = NO;
    NSDictionary* infoStore = [cacheInfoStore copy];
    [NSThread detachNewThreadSelector:@selector(archiveWithInfoStore:)
                             toTarget:self
                           withObject:infoStore];
}

- (void)archive {
    [archiveTimer invalidate];
    if ([self archiveInterval] > 0) {
        archiveTimer = [NSTimer scheduledTimerWithTimeInterval:[self archiveInterval]
														target:self
													  selector:@selector(startArchiveThread:)
													  userInfo:nil
													   repeats:NO];
    }
    wantsToArchive_ = YES;
}

- (void)archiveNow {
    [archiveTimer invalidate];
    [self startArchiveThread:nil];
    [self archive];
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
	self.cacheInfoStore = nil;
    cacheInfoStore = [self _newCacheInfoStore];
	[self archive];
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
    
    
    if (self.cacheWithoutUrlParameter)
    {
        NSArray *comps = [filepath4 componentsSeparatedByString:@"?"];
        if (comps)
        {
            filepath4 = [comps objectAtIndex:0];
        }
    }
	
    if (self.cacheWithoutHostname)
    {
        NSMutableArray *pathComps = [NSMutableArray arrayWithArray:[filepath4 pathComponents]];
        if (pathComps)
        {
            [pathComps removeObjectAtIndex:0];
            
            return [NSString pathWithComponents:pathComps];
        }
    }
    
	return filepath4;
}

- (NSString *)filePath: (NSString *) filename {
	return [dataPath stringByAppendingPathComponent: filename];
}

- (NSString *)filePath:(NSString *)filename pathExtension:(NSString *)pathExtension
{
    if (nil == pathExtension) {
        return [self filePath:filename];
    }
    else {
        return [[dataPath stringByAppendingPathComponent:filename] stringByAppendingPathExtension:pathExtension];
    }
}

- (NSString *)filePathForURL: (NSURL *) url {
	return [dataPath stringByAppendingPathComponent: [self filenameForURL: url]];
}

- (NSString *)fullPathForCacheableItem:(AFCacheableItem*)item {
	
    if (item == nil) return nil;
    
    NSString *fullPath = nil;
    
    if (self.cacheWithHashname == NO)
    {
        fullPath = [self filePathForURL:item.url];
    }
    else
    {
        fullPath = [self filePath:item.info.filename pathExtension:[item.url pathExtension]];
    }
	
#if USE_ASSERTS
    NSAssert([item.info.filename length] > 0, @"Filename length MUST NOT be zero! This is a software bug");
#endif
	
	return fullPath;
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
		} else {
            AFLog(@"Error getting file modification date: %@", [error description]);
        }
	}
	return fileDate;
}

- (NSUInteger)numberOfObjectsInDiskCache {
	if ([[NSFileManager defaultManager] fileExistsAtPath: dataPath]) {
		NSError *err;
		NSArray *directoryContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: dataPath error:&err];
        if (directoryContents == nil) {
            AFLog(@"Error getting file modification date: %@", [err description]);
        }
		return [directoryContents count];
	}
	return 0;
}

- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL)fileOnly
{
    [self removeCacheEntry:info fileOnly:fileOnly fallbackURL:nil];
}

- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL) fileOnly fallbackURL:(NSURL *)fallbackURL;
{
    if (nil == info) {
        return;
    }
	// remove redirects to this entry
	for (id redirectKey in [[self CACHED_REDIRECTS] allValues]) {
		if ([redirectKey isKindOfClass:[NSString class]]) {
			id redirectTarget = [[self CACHED_REDIRECTS] objectForKey:redirectKey];
			if ([redirectTarget isKindOfClass:[NSString class]]) {
				if([redirectTarget isEqualToString:[info.request.URL absoluteString]])
				{
					[[self CACHED_REDIRECTS] removeObjectForKey:redirectKey];
				}
			}
			
		}
	}
	
	NSError *error;
    
    NSString *filePath = nil;
    if (self.cacheWithHashname == NO)
    {
        filePath = [self filePathForURL:info.request.URL];
    }
    else
    {
        if (fallbackURL) {
            filePath = [self filePath:info.filename pathExtension:[fallbackURL pathExtension]];
        }
        else {
            filePath = [self filePath:info.filename pathExtension:[info.request.URL pathExtension]];
        }
    }
    
	if ([[NSFileManager defaultManager] removeItemAtPath: filePath error: &error]) {
		if (fileOnly==NO) {
            if (fallbackURL) {
                [[self CACHED_OBJECTS] removeObjectForKey:[fallbackURL absoluteString]];
            }
            else {
                [[self CACHED_OBJECTS] removeObjectForKey:[[info.request URL] absoluteString]];
            }
		}
	} else {
		NSLog(@ "Failed to delete file for outdated cache item info %@", info);
	}
}

#pragma mark internal core methods

- (void)updateModificationDataAndTriggerArchiving: (AFCacheableItem *) cacheableItem {
	NSError *error = nil;
	
	NSString *filePath = [self fullPathForCacheableItem:cacheableItem];
	
	/* reset the file's modification date to indicate that the URL has been checked */
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys: [NSDate date], NSFileModificationDate, nil];
	
	if (NO == [[NSFileManager defaultManager] setAttributes: dict ofItemAtPath: filePath error: &error]) {
		NSLog(@ "Failed to reset modification date for cache item %@", filePath);
	}
	[self archive];
}

- (NSFileHandle*)createFileForItem:(AFCacheableItem*)cacheableItem
{
    NSError* error = nil;
	NSString *filePath = [self fullPathForCacheableItem: cacheableItem];
	NSFileHandle* fileHandle = nil;
	// remove file if exists
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
		[self removeCacheEntry:cacheableItem.info fileOnly:YES];
		AFLog(@"removing %@", filePath);
	}
	
	// create directory if not exists
	NSString *pathToDirectory = [filePath stringByDeletingLastPathComponent];
    BOOL isDirectory = YES;
	if ( NO == [[NSFileManager defaultManager] fileExistsAtPath:pathToDirectory isDirectory:&isDirectory] || !isDirectory)
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
        if ( [[NSFileManager defaultManager] createDirectoryAtPath:pathToDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
            AFLog(@"creating directory %@", pathToDirectory);
        } else {
            AFLog(@"Failed to create directory at path %@", pathToDirectory);
        }
	}
	
	// write file
	if (maxItemFileSize == kAFCacheInfiniteFileSize || cacheableItem.info.contentLength < maxItemFileSize) {
		/* file doesn't exist, so create it */
        if (![[NSFileManager defaultManager] createFileAtPath: filePath
													 contents: nil
												   attributes: nil])
        {
            AFLog(@"Error: could not create file \"%@\"", filePath);
        }
        
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        if (fileHandle == nil) {
            AFLog(@"Could not get file handle for file at path: %@", filePath);
        }
		AFLog(@"created file at path %@ (%d)", filePath, [fileHandle fileDescriptor]);
	}
	else {
		NSLog(@ "AFCache: item %@ \nsize exceeds maxItemFileSize (%f). Won't write file to disk",cacheableItem.url, maxItemFileSize);
		[[self CACHED_OBJECTS] removeObjectForKey: [cacheableItem.url absoluteString]];
	}
    
    return fileHandle;
}

- (BOOL)_fileExistsOrPendingForCacheableItem:(AFCacheableItem*)item {
    if (item.url == nil) return NO;
    
	// the complete path
	NSString *filePath = [self fullPathForCacheableItem:item];
    
	AFLog(@"checking for file at path %@", filePath);
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: filePath])
    {
        // file doesn't exist. check if someone else is downloading the url already
        if ([[self pendingConnections] objectForKey:item.url] != nil || [self isQueuedURL:item.url])
		{
            AFLog(@"Someone else is already downloading the URL: %@.", [item.url absoluteString]);
		}
		else
		{
            AFLog(@"Cache miss for URL: %@.", [item.url absoluteString]);
            return NO;
        }
    }
    return YES;
}

// If the file exists on disk we return a new AFCacheableItem for it,
// but it may be only half loaded yet.
- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) URL {
    if (URL == nil) return nil;
	if ([[URL absoluteString] hasPrefix:@"data:"]) return nil;
	
    // the URL we use to lookup in the cache, may be changed to redirected URL
    NSURL *lookupURL = URL;
    
    // the returned cached object
    AFCacheableItem *cacheableItem = nil;
	
    
    AFCacheableItemInfo *info = [[self CACHED_OBJECTS] objectForKey: [lookupURL absoluteString]];
    if (info == nil) {
        NSString *redirectURLString = [[self CACHED_REDIRECTS] valueForKey:[URL absoluteString]];
        info = [[self CACHED_OBJECTS] objectForKey: redirectURLString];
    }
    
    if (info != nil) {
        AFLog(@"Cache hit for URL: %@", [URL absoluteString]);
		
		//        NSURLConnection *pendingConnection = [[self pendingConnections] objectForKey:URL];
        
        // check if there is an item in pendingConnections
        cacheableItem = [[self pendingConnections] objectForKey:URL];
        if (!cacheableItem) {
            cacheableItem = [[AFCacheableItem alloc] init];
            cacheableItem.cache = self;
            cacheableItem.url = URL;
            cacheableItem.info = info;
            cacheableItem.currentContentLength = 0;//info.contentLength;
            
            if (self.cacheWithHashname == NO)
            {
                cacheableItem.info.filename = [self filenameForURL:cacheableItem.url];
            }
            
            // check if file is valid
            BOOL fileExists = [self _fileExistsOrPendingForCacheableItem:cacheableItem];
            if (NO == fileExists) {
                // Something went wrong
                AFLog(@"Cache info store out of sync for url %@, removing cached file %@.", [URL absoluteString], [self fullPathForCacheableItem:cacheableItem]);
                [self removeCacheEntry:cacheableItem.info fileOnly:YES];
                cacheableItem = nil;
            }
			else
			{
				//make sure that we continue downloading by setting the length
				cacheableItem.info.cachePath = [self fullPathForCacheableItem:cacheableItem];
				//currently done by reading out file lenth in the info.actualLength accessor
				/*NSString *filePath = [self fullPathForCacheableItem:cacheableItem];
				 NSData* fileContent = [NSData dataWithContentsOfFile:filePath];
				 cacheableItem.currentContentLength = [fileContent length];
				 cacheableItem.data = fileContent;*/
			}
        }
        [cacheableItem validateCacheStatus];
        if ([self isOffline]) {
            cacheableItem.cacheStatus = kCacheStatusFresh;
        }
    }
    
    return cacheableItem;
}



- (void)cancelConnectionsForURL: (NSURL *) url
{
	if (nil != url)
	{
        AFCacheableItem *pendingItem = [pendingConnections objectForKey: url];
		AFLog(@"Cancelling connection for URL: %@", [url absoluteString]);
        pendingItem.delegate = nil;
        pendingItem.completionBlock = nil;
        pendingItem.failBlock = nil;
        pendingItem.progressBlock = nil;
		[pendingItem.connection cancel];
		[pendingConnections removeObjectForKey: url];
	}
}

- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)aDelegate
{
    if (nil != url)
    {
        [self cancelConnectionsForURL:url];
		
        [self removeClientItemForURL:url itemDelegate:aDelegate];
    }
}
- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)itemDelegate didLoadSelector:(SEL)selector
{
	if (nil != itemDelegate)
    {
        NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
        
        for (AFCacheableItem* item in [clientItemsForURL copy])
        {
            if (itemDelegate == item.delegate &&
                selector == item.connectionDidFinishSelector)
            {
                [self removeFromDownloadQueue:item];
                item.delegate = nil;
                item.completionBlock = nil;
                item.failBlock = nil;
                item.progressBlock = nil;
                [self cancelConnectionsForURL:url];
                
                [clientItemsForURL removeObjectIdenticalTo:item];
                
                if ( ![clientItemsForURL count] )
                {
                    [clientItems removeObjectForKey:url];
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
            
            for (AFCacheableItem* item in [clientItemsForURL copy])
            {
                if (itemDelegate == item.delegate )
                {
                    [self removeFromDownloadQueue:item];
					item.delegate = nil;
                    item.completionBlock = nil;
                    item.failBlock = nil;
                    item.progressBlock = nil;
                    [self cancelConnectionsForURL:url];
					
                    [clientItemsForURL removeObjectIdenticalTo:item];
                    
                    if ( ![clientItemsForURL count] )
                    {
                        [clientItems removeObjectForKey:url];
                    }
                }
            }
        }
		
		[self fillPendingConnections];
    }
}

- (void)cancelPendingConnections
{
    for (AFCacheableItem* pendingItem in [pendingConnections allValues])
    {
        [pendingItem.connection cancel];
    }
    [pendingConnections removeAllObjects];
}

- (void)cancelAllClientItems
{
    [self cancelPendingConnections];
    
    for (NSArray* items in [clientItems allValues])
    {
        for (AFCacheableItem* item in items)
        {
            item.delegate = nil;
            item.completionBlock = nil;
            item.failBlock = nil;
            item.progressBlock = nil;
        }
    }
    
    [clientItems removeAllObjects];
}



- (void)removeReferenceToConnection: (NSURLConnection *) connection {
    NSArray *pendingItems = [NSArray arrayWithArray:[pendingConnections allValues]];
    for (AFCacheableItem *item in pendingItems) {
        if (item.connection == connection) {
            [pendingConnections removeObjectForKey:item.url];
        }
    }
}

- (void)registerClientItem:(AFCacheableItem*)itemToRegister
{
    NSURL *URLKey = itemToRegister.url;
    NSMutableArray* existingClientItems = [clientItems objectForKey:URLKey];
    if (nil == existingClientItems) {
        existingClientItems = [NSMutableArray array];
        [clientItems setObject:existingClientItems forKey:URLKey];
    }
    [existingClientItems addObject:itemToRegister];
}

- (NSArray*)clientItemsForURL:(NSURL*)url
{
    return [[clientItems objectForKey:url] copy];
}

- (void)signalClientItemsForURL:(NSURL*)url usingSelector:(SEL)selector
{
    NSArray* items = [self clientItemsForURL:url];
	
    for (AFCacheableItem* item in items)
    {
        id delegate = item.delegate;
        if ([delegate respondsToSelector:selector]) {
            [delegate performSelector:selector withObject:item];
        }
    }
}

- (void)removeClientItemsForURL:(NSURL*)url {
    NSArray* items = [clientItems objectForKey:url];
    [downloadQueue removeObjectsInArray:items];
	[clientItems removeObjectForKey:url];
}


- (void)removeClientItemForURL:(NSURL*)url itemDelegate:(id)itemDelegate
{
	NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
	// TODO: if there are more delegates on an item, then do not remove the whole item, just set the corrensponding delegate to nil and let the item there for remaining delegates
	for ( AFCacheableItem* item in [clientItemsForURL copy] )
	{
		if ( itemDelegate == item.delegate )
		{
			[self removeFromDownloadQueue:item];
			item.delegate = nil;
            item.completionBlock = nil;
            item.failBlock = nil;
            item.progressBlock = nil;
            
			[clientItemsForURL removeObjectIdenticalTo:item];
			
			if ( ![clientItemsForURL count] )
			{
				[clientItems removeObjectForKey:url];
			}
		}
	}
	[self fillPendingConnections];
}

- (void)handleDownloadItem:(AFCacheableItem*)item ignoreQueue:(BOOL)ignoreQueue {
    if (ignoreQueue) {
        if ((item != nil) && ![item isDownloading]) {
            [self downloadItem:item];
        }
    } else {
        [self addItemToDownloadQueue:item];
    }
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
	for (AFCacheableItem *item in [downloadQueue copy])
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

- (NSArray*)itemsInDownloadQueue
{
    return self->downloadQueue;
}

- (void)prioritizeURL:(NSURL*)url
{
    // find the item that is actually downloading and put it into the pole position
    for (AFCacheableItem* cacheableItem in [self clientItemsForURL:url])
    {
        if ([downloadQueue containsObject:cacheableItem])
        {
            [downloadQueue removeObject:cacheableItem];
            [downloadQueue insertObject:cacheableItem atIndex:0];
        }
    }
}



- (void)prioritizeItem:(AFCacheableItem*)item
{
	[self prioritizeURL:item.url];
}



// Download item if we need to.
- (void)downloadItem:(AFCacheableItem*)item
{
	if (self.pauseDownload == YES)
	{
		// Do not start any connection right now, because AFCache is paused
		return;
	}
    //check if we can download
    if (![item.url isFileURL] && [self isOffline]) {
        //we can not download this item at the moment
        if(item.failBlock != nil)
        {
            item.failBlock(item);
        }
        return;
    }
    
    AFLog(@"downloading %@",item.url);
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
	
	NSMutableURLRequest *theRequest = item.info.request?:[NSMutableURLRequest requestWithURL: item.url
                                                                                 cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
                                                                             timeoutInterval: timeout];
	
#ifdef RESUMEABLE_DOWNLOAD
	uint64_t dataAlreadyDownloaded = item.info.actualLength;
	NSString* rangeToDownload = [NSString stringWithFormat:@"%lld-",dataAlreadyDownloaded];
	uint64_t expectedFileSize = item.info.contentLength;
	if(expectedFileSize > 0)
		rangeToDownload = [rangeToDownload stringByAppendingFormat:@"%lld",expectedFileSize];
	AFLog(@"range %@",rangeToDownload);
	[theRequest setValue:rangeToDownload forHTTPHeaderField:@"Range"];
#endif
	
    [theRequest setValue:@"" forHTTPHeaderField:AFCacheInternalRequestHeader];
    
    item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
    item.info.responseTimestamp = 0.0;
    item.info.request = theRequest;
    
    ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(theRequest.URL);
    
	
    NSURLConnection *connection = [[NSURLConnection alloc]
								   initWithRequest:theRequest
								   delegate:item
								   startImmediately:YES];
    item.connection = connection;
    [pendingConnections setObject: item forKey: item.url];
    
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

#pragma mark offline & pause methods

- (void)setPauseDownload:(BOOL)pause
{
    
	pauseDownload_ = pause;
	
	if (pause == YES)
	{
        [packageArchiveQueue_ setSuspended:YES];
		// Check for running connection -> add the items to the queue again
        NSMutableArray* allItems = [NSMutableArray array];
		for (NSURL* url in [pendingConnections allKeys])
		{
            [allItems addObjectsFromArray:[clientItems objectForKey:url]];
        }
        
        [self cancelPendingConnections];
        
        for (AFCacheableItem* item in allItems)
        {
            if (![downloadQueue containsObject:item])
            {
                [downloadQueue insertObject:item atIndex:0];   // retain count +1 because we are removing it from clientItems afterwards (which decreases the retain count again)
            }
        }
	}
	else
	{
        [packageArchiveQueue_ setSuspended:NO];
		// Resume downloading
		for (int i = 0; i < concurrentConnections; i++)
		{
			if ([[pendingConnections allKeys] count] < concurrentConnections)
			{
				[self downloadNextEnqueuedItem];
			}
		}
		
	}
    
}

- (void)setOffline:(BOOL)value {
	_offline = value;
}

- (BOOL)isOffline {
	return /*![self isConnectedToNetwork] || */ _offline==YES || !self.downloadPermission;
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
	BOOL isReachable = (flags & kSCNetworkFlagsReachable) == kSCNetworkFlagsReachable;
	BOOL needsConnection = (flags & kSCNetworkFlagsConnectionRequired) == kSCNetworkFlagsConnectionRequired;
    
	return isReachable && !needsConnection;
}

- (void)setConnectedToNetwork:(BOOL)connected
{
    if (self->isConnectedToNetwork_ != connected)
    {
        [self willChangeValueForKey:@"isConnectedToNetwork"];
        self->isConnectedToNetwork_ = connected;
        [self didChangeValueForKey:@"isConnectedToNetwork"];
    }
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

@implementation AFCache( BLOCKS )
#if NS_BLOCKS_AVAILABLE

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
								options: (int) options
{
    
    
    return [self cachedObjectForURL: url
                    completionBlock: aCompletionBlock
                          failBlock: aFailBlock
                            options: options
                           userData: nil
                           username: nil
                           password: nil];
}


- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
								options: (int) options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword
{
    
    AFCacheableItem *item = [self cachedObjectForURL:url
                                            delegate:nil
                                            selector:nil
                                     didFailSelector:nil
                                     completionBlock:aCompletionBlock
                                           failBlock:aFailBlock
                                       progressBlock:nil
                                             options:options
                                            userData:userData
                                            username:aUsername
                                            password:aPassword
                                             request:nil];
    
    
    
    return item;
	
}




- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
                          progressBlock: (AFCacheableItemBlock)aProgressBlock
								options: (int) options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword
{
    AFCacheableItem *item = [self cachedObjectForURL:url
                                            delegate:nil
                                            selector:nil
                                     didFailSelector:nil
                                     completionBlock:aCompletionBlock
                                           failBlock:aFailBlock
                                       progressBlock:aProgressBlock
                                             options:options
                                            userData:userData
                                            username:aUsername
                                            password:aPassword
											 request:nil];
    
    
    
    return item;
}


- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
                          progressBlock: (AFCacheableItemBlock)aProgressBlock
								options: (int) options
{
    
    
    return [self cachedObjectForURL: url
                    completionBlock: aCompletionBlock
                          failBlock: aFailBlock
                      progressBlock: aProgressBlock
                            options: options
                           userData: nil
                           username: nil
                           password: nil];
}


#endif

-(BOOL)persistDownloadQueue
{
	return [downloadQueue writeToFile:@"downloadQueueStore" atomically:YES];
}

#pragma mark Debug Helper

-(NSArray*)cachedObjectAllKeys
{
	return [[cacheInfoStore valueForKey:kAFCacheInfoStoreCachedObjectsKey] allKeys];
}

-(NSArray*)redirectsAllKeys
{
	return [[cacheInfoStore valueForKey:kAFCacheInfoStoreRedirectsKey] allKeys];
}

@end

