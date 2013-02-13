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

#define CACHED_OBJECTS [cacheInfoStore valueForKey:kAFCacheInfoStoreCachedObjectsKey]
#define CACHED_REDIRECTS [cacheInfoStore valueForKey:kAFCacheInfoStoreRedirectsKey]

#if USE_ASSERTS
#define ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(url) NSAssert( [(url) isFileURL] || [self isOffline] == NO, @"No connection should be opened if we're in offline mode - this seems like a bug")
#else
#define ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(url) do{}while(0)
#endif


const char* kAFCacheContentLengthFileAttribute = "de.artifacts.contentLength";
const char* kAFCacheDownloadingFileAttribute = "de.artifacts.downloading";
const double kAFCacheInfiniteFileSize = 0.0;
const double kAFCacheArchiveDelay = 5.0;

extern NSString* const UIApplicationWillResignActiveNotification;

@interface AFCache()
- (void)archiveWithInfoStore:(NSDictionary*)infoStore;
- (void)cancelAllClientItems;
- (id)initWithContext:(NSString*)context;
@end

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;
static NSString* AFCache_rootPath = nil;
static NSMutableDictionary* AFCache_contextCache = nil;

@synthesize cacheEnabled, dataPath, cacheInfoStore, pendingConnections, maxItemFileSize, diskCacheDisplacementTresholdSize, suffixToMimeTypeMap, networkTimeoutIntervals;
@synthesize clientItems;
@synthesize concurrentConnections;
@synthesize pauseDownload = pauseDownload_;
@synthesize downloadPermission = downloadPermission_;
@synthesize packageInfos;
@synthesize failOnStatusCodeAbove400;
@synthesize cacheWithoutUrlParameter;
@synthesize cacheWithoutHostname;
@synthesize userAgent;
@synthesize disableSSLCertificateValidation;
@synthesize cacheWithHashname;
@dynamic isConnectedToNetwork;

#pragma mark init methods

- (id)initWithContext:(NSString*)context {
    if (nil == context && sharedAFCacheInstance != nil)
    {
        [self release];
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
            [AFCache_contextCache setObject:[NSValue valueWithPointer:self] forKey:context];
        }
        
        context_ = [context copy];
        isInstancedCache_ = (context != nil);
        self.downloadPermission = YES;
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
    [dataPath autorelease];
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

+ (NSString*)rootPath
{
    if (nil == AFCache_rootPath)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        AFCache_rootPath = [[paths objectAtIndex: 0] copy];
    }
    return AFCache_rootPath;
}

+ (void)setRootPath:(NSString *)rootPath
{
    if (AFCache_rootPath != rootPath)
    {
        [AFCache_rootPath release];
    }
    AFCache_rootPath = [rootPath copy];
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
        cache = [[[[self class] alloc] initWithContext:context] autorelease];
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
    
	cacheEnabled = YES;
	failOnStatusCodeAbove400 = YES;
    cacheWithHashname = YES;
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
	
	[downloadQueue release];
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
    if ([self isOffline]) return; // don't cleanup if we're offline
	unsigned long size = [self diskCacheSize];
	if (size < diskCacheDisplacementTresholdSize) return;
	NSDate *now = [NSDate date];
	NSArray *keys = nil;
	NSString *key = nil;
	for (AFCacheableItemInfo *info in [CACHED_OBJECTS allValues]) {
		if (info.expireDate == [now earlierDate:info.expireDate]) {
			keys = [CACHED_OBJECTS allKeysForObject:info];
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

// The CACHED_REDIRECTS dictionary has the redirected URL as KEY and the orginal URL as VALUE
- (NSURL*)redirectURLForURL:(NSURL*)anURL {    
    NSURL *originalURL = nil;
    for (NSString *redirectURL in [CACHED_REDIRECTS allKeys]) {        
        originalURL = [CACHED_REDIRECTS valueForKey:redirectURL];
        if ([originalURL isEqual:anURL]) {
            return [NSURL URLWithString:redirectURL];   
        }
    }
    return nil;
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
    if (url == nil || [[url absoluteString] length] == 0)
    {
        NSError *error = [NSError errorWithDomain:@"URL is not set" code:-1 userInfo:nil];
        AFCacheableItem *item = [[[AFCacheableItem alloc] init] autorelease];
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
    
	AFCacheableItem *item = nil;
    BOOL didRewriteURL = NO; // the request URL might be rewritten by the cache internally if we're offline because the
                             // redirect mechanisms in the URL loading system / UIWebView do not seem to work well when
                             // no network connection is available. 
    
	if (url != nil) {
		NSURL *internalURL = url;
        
        if ([self isOffline] == YES) {
            // We're offline. In this case, we lookup if we have a cached redirect
            // and change the origin URL to the redirected Location.
            NSURL *redirectURL = [self redirectURLForURL:url];
            if (redirectURL) {
                internalURL = redirectURL;
                didRewriteURL = YES;
            }
        }
		
		// try to get object from disk
		if (self.cacheEnabled && invalidateCacheEntry == 0) {
			item = [self cacheableItemFromCacheStore: internalURL];


            if ([self isOffline] && !item) {
                // check if there is a cached redirect for this URL, but ONLY if we're offline                
                // AFAIU redirects of type 302 MUST NOT be cached
                // since we do not distinguish between 301 and 302 or other types of redirects, nor save the status code anywhere
                // we simply only check the cached redirects if we're offline
                // see http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html 13.4 Response Cacheability
                internalURL = [CACHED_REDIRECTS valueForKey:[url absoluteString]];
                item = [self cacheableItemFromCacheStore: internalURL];                
            }
			            
            // check validity of cached item
            if (![item isDataLoaded] &&
                ([item hasDownloadFileAttribute] || ![item hasValidContentLength])) {

                if (nil == [pendingConnections objectForKey:internalURL])
				{
					item = nil;
				}
			}
 		}
        
        BOOL performGETRequest = NO; // will be set to YES if we're online and have a cache miss
        
		if (!item) {            
            // we're offline and did not have a cached version, so return nil
            if ([self isOffline]) return nil;
            
            // we're online - create a new item, since we had a cache miss
            item = [[[AFCacheableItem alloc] init] autorelease];
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
        item.servedFromCache = performGETRequest ? NO : YES;
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
            [CACHED_OBJECTS setObject:item.info forKey:[internalURL absoluteString]];		
            // Register item so that signalling works (even with fresh items 
            // from the cache).
            [self registerItem:item];            
            [self addItemToDownloadQueue:item];
            return item;
		} else {
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
            [self registerItem:item];
            
            // Check if item is fully loaded already
            if (item.canMapData && nil == item.data && ![item hasValidContentLength])
            {
                [self addItemToDownloadQueue:item];
                return item;
            }
            
            // Item is fresh, so call didLoad selector and return the cached item.
            if ([item isFresh] || neverRevalidate)
            {
                
                item.cacheStatus = kCacheStatusFresh;
                item.currentContentLength = item.info.contentLength;
                //item.info.responseTimestamp = [NSDate timeIntervalSinceReferenceDate];
                [item performSelector:@selector(connectionDidFinishLoading:) withObject:nil];
                AFLog(@"serving from cache: %@", item.url);
                return item;
            }
            // Item is not fresh, fire an If-Modified-Since request
            else
            {
                // reset data, because there may be old data set already
                item.data = nil;
                
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
                
                [self addItemToDownloadQueue:item];
                
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

//#if MAINTAINER_WARNINGS
//#warning BK: this is in support of using file urls with ste-engine - no info yet for shortCircuiting
//#endif
//    if( [url isFileURL] ) {
//        AFCacheableItem *shortCircuitItem = [[[AFCacheableItem alloc] init] autorelease];
//        shortCircuitItem.data = [NSData dataWithContentsOfURL: url];
//        return shortCircuitItem;
//    }

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
    
    
    if (self.cacheWithoutUrlParameter == YES)
    {
        NSArray *comps = [filepath4 componentsSeparatedByString:@"?"];
        if (comps)
        {
            filepath4 = [comps objectAtIndex:0];
        } 
    }

    if (self.cacheWithoutHostname == YES)
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

- (NSString *)filePathForURL: (NSURL *) url {
	return [dataPath stringByAppendingPathComponent: [self filenameForURL: url]];
}

- (NSString *)fullPathForCacheableItem:(AFCacheableItem*)item {

    NSString *fullPath = nil;
    
    if (self.cacheWithHashname == NO)
    {
        fullPath = [self filePathForURL: item.url];
    }
    else
    {
        fullPath = [self filePath:item.info.filename];
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

- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL) fileOnly {
	NSError *error;
    NSString *filePath = [self filePath:info.filename];
	if (YES == [[NSFileManager defaultManager] removeItemAtPath: filePath error: &error]) {
		if (fileOnly==NO) {
			[CACHED_OBJECTS removeObjectForKey:[[info.request URL] absoluteString]];
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
	[dict release];	
	[self archive];
}

- (NSFileHandle*)createFileForItem:(AFCacheableItem*)cacheableItem
{
    NSError* error = nil;
	NSString *filePath = [self fullPathForCacheableItem: cacheableItem];
	NSFileHandle* fileHandle = nil;
	// remove file if exists
	if (YES == [[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
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
        if ( YES == [[NSFileManager defaultManager] createDirectoryAtPath:pathToDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
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
		[CACHED_OBJECTS removeObjectForKey: [cacheableItem.url absoluteString]];
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

    
    AFCacheableItemInfo *info = [CACHED_OBJECTS objectForKey: [lookupURL absoluteString]];
    if (info == nil) {
        NSURL *redirectURL = [CACHED_REDIRECTS valueForKey:[URL absoluteString]];
        info = [CACHED_OBJECTS objectForKey: [redirectURL absoluteString]];
    }
    
    if (info != nil) {
        AFLog(@"Cache hit for URL: %@", [URL absoluteString]);

        cacheableItem = [[[AFCacheableItem alloc] init] autorelease];
        cacheableItem.cache = self;
        cacheableItem.url = URL;
        cacheableItem.info = info;
        cacheableItem.currentContentLength = info.contentLength;        
        
        if (self.cacheWithHashname == NO)
        {
            cacheableItem.info.filename = [self filenameForURL:cacheableItem.url];
        }
        
        // check if file is valid
        BOOL fileExists = [self _fileExistsOrPendingForCacheableItem:cacheableItem];
        if (NO == fileExists) {
            // Something went wrong
            AFLog(@"Cache info store out of sync for url %@, removing cached file %@.", [URL absoluteString], filePath);
            [self removeCacheEntry:cacheableItem.info fileOnly:YES];
            cacheableItem = nil;
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
    }
}
- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)itemDelegate didLoadSelector:(SEL)selector
{
	if (nil != itemDelegate)
    {
        NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
        
        for (AFCacheableItem* item in [[clientItemsForURL copy] autorelease])
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
            
            for (AFCacheableItem* item in [[clientItemsForURL copy] autorelease])
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
    for (NSURLConnection* connection in [pendingConnections allValues])
    {
        [connection cancel];
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

- (NSArray*)cacheableItemsForDelegate:(id)delegate didFinishSelector:(SEL)didFinishSelector
{
    if (nil != delegate)
    {
        NSMutableArray* items = [NSMutableArray array];
        NSArray *allKeys = [clientItems allKeys];
		for (NSURL *url in allKeys)
        {
            NSMutableArray* const clientItemsForURL = [clientItems objectForKey:url];
            
            for (AFCacheableItem* item in [[clientItemsForURL copy] autorelease])
            {
                if (delegate == item.delegate &&
                    item.connectionDidFinishSelector == didFinishSelector)
                {
                    [items addObject:item];
                }
            }
        }
        
        if ([items count] != 0)
        {
            return items;
        }
    }
    
    return nil;
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
    NSArray* items = [clientItems objectForKey:url];
    [downloadQueue removeObjectsInArray:items];
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

- (NSArray*)itemsInDownloadQueue
{
    return self->downloadQueue;
}

- (void)prioritizeURL:(NSURL*)url
{
    // find the item that is actually downloading and put it into the pole position
    for (AFCacheableItem* cacheableItem in [self cacheableItemsForURL:url])
    {
        if ([downloadQueue containsObject:cacheableItem])
        {
            [cacheableItem retain];
            [downloadQueue removeObject:cacheableItem];
            [downloadQueue insertObject:cacheableItem atIndex:0];
            [cacheableItem release];
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
    
    [theRequest setValue:@"" forHTTPHeaderField:AFCacheInternalRequestHeader];
    
    item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
    item.info.responseTimestamp = 0.0;
    item.info.request = theRequest;
    
    ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(theRequest.URL);
    

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
    
	BOOL connected = (isReachable && !needsConnection) ? YES : NO;
    
    return connected;
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

/*
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

- (oneway void)release {
}

- (id)autorelease {
	return self;
}
=======
//+ (id)allocWithZone: (NSZone *) zone {
//	@synchronized(self) {
//		if (sharedAFCacheInstance == nil) {
//			sharedAFCacheInstance = [super allocWithZone: zone];
//			return sharedAFCacheInstance;  // assignment and return on first allocation
//		}
//	}
//	return nil; //on subsequent allocation attempts return nil
//}
//
//- (id)copyWithZone: (NSZone *) zone {
//	return self;
//}
//
//- (id)retain {
//	return self;
//}
//
//- (NSUInteger)retainCount {
//	return UINT_MAX;  //denotes an object that cannot be released
//}
//
//- (void)release {
//}
//
//- (id)autorelease {
//	return self;
//}

 */

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
	[archiveTimer release];
	[suffixToMimeTypeMap release];
	self.pendingConnections = nil;
	[downloadQueue release];
	self.cacheInfoStore = nil;
	
	[clientItems release];
	[dataPath release];
	[packageInfos release];
	
    if (nil != context_)
    {
        [AFCache_contextCache removeObjectForKey:context_];
    }
    
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
@end

