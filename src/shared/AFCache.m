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
#import "DateParser.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#include <sys/xattr.h>
#import "AFRegexString.h"
#import "AFCache_Logging.h"

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

@property (nonatomic, copy) NSString *context;
@property (nonatomic, strong) NSMutableArray *downloadQueue;
@property (nonatomic, strong) NSTimer *archiveTimer;
@property (nonatomic, assign) BOOL wantsToArchive;
@property (nonatomic, assign) BOOL connectedToNetwork;
@property (nonatomic, strong) NSOperationQueue *packageArchiveQueue;

- (void)serializeState:(NSDictionary*)infoStore;
- (void)cancelAllClientItems;
- (id)initWithContext:(NSString*)context;
@end

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;
static NSMutableDictionary* AFCache_contextCache = nil;

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
    if (!context && sharedAFCacheInstance != nil)
    {
        return [AFCache sharedInstance];
    }
    
    self = [super init];
    
	if (self) {
		
#if TARGET_OS_IPHONE
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(serializeState)
                                                     name:UIApplicationWillResignActiveNotification
                                                   object:nil];
		
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(serializeState)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
#endif
        if (!AFCache_contextCache) {
            AFCache_contextCache = [[NSMutableDictionary alloc] init];
        }
        
        if (context) {
            [AFCache_contextCache setObject:[NSValue valueWithPointer:(__bridge const void *)(self)] forKey:context];
        }
        
        _context = [context copy];
        [self reinitialize];
		[self initMimeTypes];
	}
	return self;
}

- (void)initialize {
    _downloadPaused = NO;
    _downloadPermission = YES;
    _wantsToArchive = NO;
    _connectedToNetwork = NO;
    _archiveInterval = kAFCacheArchiveDelay;
    _cacheEnabled = YES;
    _failOnStatusCodeAbove400 = YES;
    _cacheWithHashname = YES;
    _maxItemFileSize = kAFCacheInfiniteFileSize;
    _networkTimeoutIntervals.IMSRequest = kDefaultNetworkTimeoutIntervalIMSRequest;
    _networkTimeoutIntervals.GETRequest = kDefaultNetworkTimeoutIntervalGETRequest;
    _networkTimeoutIntervals.PackageRequest = kDefaultNetworkTimeoutIntervalPackageRequest;
    _concurrentConnections = kAFCacheDefaultConcurrentConnections;
    _totalRequestsForSession = 0;
    _offline = NO;
    _pendingConnections = [[NSMutableDictionary alloc] init];
    _downloadQueue = [[NSMutableArray alloc] init];
    _clientItems = [[NSMutableDictionary alloc] init];
    _packageArchiveQueue = [[NSOperationQueue alloc] init];
    [_packageArchiveQueue setMaxConcurrentOperationCount:1];

    if (!_dataPath)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *appId = [@"afcache" stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
        _dataPath = [[[paths objectAtIndex: 0] stringByAppendingPathComponent: appId] copy];
    }

    [self deserializeState];

    /* check for existence of cache directory */
    if ([[NSFileManager defaultManager] fileExistsAtPath: _dataPath]) {
        AFLog(@ "Successfully unarchived cache store");
    }
    else {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath: _dataPath
                                       withIntermediateDirectories: YES
                                                        attributes: nil
                                                             error: &error]) {
            AFLog(@ "Failed to create cache directory at path %@: %@", _dataPath, [error description]);
        }
    }

#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1 || TARGET_OS_MAC && MAC_OS_X_VERSION_MIN_ALLOWED < MAC_OS_X_VERSION_10_8
    [self addSkipBackupAttributeToItemAtURL:[NSURL fileURLWithPath:_dataPath]];
#endif
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_context)
    {
        [AFCache_contextCache removeObjectForKey:_context];
    }

}

- (NSUInteger)requestsPending {
	return [self.pendingConnections count];
}

- (void)setDataPath:(NSString*)newDataPath {
    if (self.context && self.dataPath)
    {
        NSLog(@"Error: Can't change data path on instanced AFCache");
        NSAssert(NO, @"Can't change data path on instanced AFCache");
        return;
    }
    if (self.wantsToArchive) {
        [self serializeState];
    }
    _dataPath = [newDataPath copy];
    double fileSize = self.maxItemFileSize;
    [self reinitialize];
    self.maxItemFileSize = fileSize;
}

// TODO: If we really need "named" caches ("context" is the wrong word), then realize this concept as a category, but not here
+ (AFCache*)cacheForContext:(NSString *)context
{
    if (!AFCache_contextCache)
    {
        AFCache_contextCache = [[NSMutableDictionary alloc] init];
    }
    
    if (!context)
    {
        return [self sharedInstance];
    }
    
    AFCache* cache = [[AFCache_contextCache objectForKey:context] pointerValue];
    if (!cache)
    {
        cache = [[[self class] alloc] initWithContext:context];
    }
    
    return cache;
}

// The method reinitialize really initializes the cache.
// This is usefull for testing, when you want to, uh, reinitialize

- (void)reinitialize {
    if (self.wantsToArchive) {
        [self serializeState];
    }
    [self cancelAllClientItems];

    [self initialize];
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
	[self.urlRedirects setObject:[redirectURL absoluteString] forKey:[originalURL absoluteString]];
}

-(void)addRedirectFromURLString:(NSString*)originalURLString toURLString:(NSString*)redirectURLString
{
	[self.urlRedirects setObject:redirectURLString forKey:originalURLString];
}

// remove all expired cache entries
// TODO: exchange with a better displacement strategy
- (void)doHousekeeping {
    if ([self isOffline]) return; // don't cleanup if we're offline
	unsigned long size = [self diskCacheSize];
	if (size < self.diskCacheDisplacementTresholdSize) return;
	NSDate *now = [NSDate date];
	NSArray *keys = nil;
	NSString *key = nil;
	for (AFCacheableItemInfo *info in [self.cachedItemInfos allValues]) {
		if (info.expireDate != nil && info.expireDate == [now earlierDate:info.expireDate]) {
			keys = [self.cachedItemInfos allKeysForObject:info];
			if ([keys count] > 0) {
				key = [keys objectAtIndex:0];
				[self removeCacheEntry:info fileOnly:NO];
                NSString* fullPath = [self.dataPath stringByAppendingPathComponent:key];
				[self removeCacheEntryWithFilePath:fullPath fileOnly:NO];
			}
		}
	}
}

- (void)removeCacheEntryWithFilePath:(NSString *)filePath fileOnly:(BOOL)fileOnly {
    // TODO: Implement me or remove me (I am called in doHousekeeping)
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
    if (err)
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

#pragma mark - Public API for getting cached items (do not use any other)

- (AFCacheableItem*)cacheItemForURL:(NSURL *)url
                      urlCredential:(NSURLCredential *)urlCredential
                     completionBlock:(AFCacheableItemBlock)completionBlock
                           failBlock:(AFCacheableItemBlock)failBlock
{
    // delegate to our internal method
    return [self _internalCacheItemForURL:url
                            urlCredential:urlCredential
                          completionBlock:completionBlock
                                failBlock:failBlock
                            progressBlock:nil
                     requestConfiguration:nil];
}

- (AFCacheableItem*)cacheItemForURL:(NSURL *)url
                      urlCredential:(NSURLCredential *)urlCredential
                     completionBlock:(AFCacheableItemBlock)completionBlock
                           failBlock:(AFCacheableItemBlock)failBlock
                       progressBlock:(AFCacheableItemBlock)progressBlock
{
    // delegate to our internal method
    return [self _internalCacheItemForURL:url
                            urlCredential:urlCredential
                          completionBlock:completionBlock
                                failBlock:failBlock
                            progressBlock:progressBlock
                     requestConfiguration:nil];
}

- (AFCacheableItem*)cacheItemForURL:(NSURL *)url
                      urlCredential:(NSURLCredential *)urlCredential
                     completionBlock:(AFCacheableItemBlock)completionBlock
                           failBlock:(AFCacheableItemBlock)failBlock
                       progressBlock:(AFCacheableItemBlock)progressBlock
                requestConfiguration:(AFRequestConfiguration*)requestConfiguration
{
    // delegate to our internal method
    return [self _internalCacheItemForURL:url
                            urlCredential:urlCredential
                           completionBlock:completionBlock
                                 failBlock:failBlock
                             progressBlock:progressBlock
                     requestConfiguration:requestConfiguration];
}

- (AFCacheableItem*)_internalCacheItemForURL:(NSURL *)url urlCredential:(NSURLCredential *)urlCredential completionBlock:(AFCacheableItemBlock)completionBlock failBlock:(AFCacheableItemBlock)failBlock progressBlock:(AFCacheableItemBlock)progressBlock requestConfiguration:(AFRequestConfiguration*)requestConfiguration
{
	// validate URL and handle invalid url
    if (![self isValidRequestURL:url]) {
        [self handleInvalidURLRequest:failBlock];
        return nil;
    }

    // increase count of request in this session
	_totalRequestsForSession++;
    
    // extract option-parts from requestConfiguration.options
    BOOL invalidateCacheEntry = (requestConfiguration.options & kAFCacheInvalidateEntry) != 0;
    BOOL revalidateCacheEntry = (requestConfiguration.options & kAFCacheRevalidateEntry) != 0;
    BOOL justFetchHTTPHeader = (requestConfiguration.options & kAFCacheJustFetchHTTPHeader) != 0;
    BOOL shouldIgnoreQueue = (requestConfiguration.options & kAFCacheIgnoreDownloadQueue) != 0;
    BOOL isPackageArchive = (requestConfiguration.options & kAFCacheIsPackageArchive) != 0;
    BOOL neverRevalidate = (requestConfiguration.options & kAFCacheNeverRevalidate) != 0;
    
	AFCacheableItem *item = nil;
    
    BOOL didRewriteURL = NO; // the request URL might be rewritten by the cache internally if we're offline because the
	// redirect mechanisms in the URL loading system / UIWebView do not seem to work well when
	// no network connection is available.
    
    NSURL *internalURL = url;
    
    if ([self isOffline]) {
        // We are offline. In this case, we lookup if we have a cached redirect
        // and change the origin URL to the redirected Location.
        NSURL *redirectURL = [self.urlRedirects valueForKey:[url absoluteString]];
        if (redirectURL) {
            internalURL = redirectURL;
            didRewriteURL = YES;
        }
    }
    
    // try to get object from disk
    if (self.cacheEnabled && !invalidateCacheEntry) {
        item = [self cacheableItemFromCacheStore: internalURL];
        
        if (!internalURL.isFileURL && [self isOffline] && !item) {
            // check if there is a cached redirect for this URL, but ONLY if we're offline
            // AFAIU redirects of type 302 MUST NOT be cached
            // since we do not distinguish between 301 and 302 or other types of redirects, nor save the status code anywhere
            // we simply only check the cached redirects if we're offline
            // see http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html 13.4 Response Cacheability
            internalURL = [NSURL URLWithString:[self.urlRedirects valueForKey:[url absoluteString]]];
            item = [self cacheableItemFromCacheStore: internalURL];
        }
        
        // check validity of cached item
        if (![item isDataLoaded] &&//TODO: validate this check (does this ensure that we continue downloading but also detect corrupt files?)
            ([item hasDownloadFileAttribute] || ![item hasValidContentLength])) {
            
            if (![self.pendingConnections objectForKey:internalURL]) {
                //item is not vailid and not allready being downloaded, set item to nil to trigger download
                item = nil;
            }
        }
    }
    
    BOOL performGETRequest = NO; // will be set to YES if we're online and have a cache miss
    
    if (!item) {
        // if we are offline and do not have a cached version, so return nil
        if (!internalURL.isFileURL && [self isOffline]) {
            if (failBlock != nil) {
                failBlock(nil);
            }
            return nil;
        }
        
        // we're online - create a new item, since we had a cache miss
        item = [[AFCacheableItem alloc] init];
        performGETRequest = YES;
    }
    
    // setup item
    item.tag = self.totalRequestsForSession;
    item.cache = self; // calling this particular setter does not increase the retain count to avoid a cyclic reference from a cacheable item to the cache.
    item.url = internalURL;
    item.userData = requestConfiguration.userData;
    item.urlCredential = urlCredential;
    item.justFetchHTTPHeader = justFetchHTTPHeader;
    item.isPackageArchive = isPackageArchive;
    item.URLInternallyRewritten = didRewriteURL;
    item.servedFromCache = performGETRequest ? NO : YES; //!performGETRequest
    item.info.request = requestConfiguration.request;
    
    if (self.cacheWithHashname == NO) {
        item.info.filename = [self filenameForURL:item.url];
    }
    
    item.completionBlock = completionBlock;
    item.failBlock = failBlock;
    item.progressBlock = progressBlock;
    
    if (performGETRequest) {
        // perform a request for our newly created item
        [self.cachedItemInfos setObject:item.info forKey:[internalURL absoluteString]];
        
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
            if (item.data) {
                [item performSelector:@selector(signalItemsDidFinish:)
                           withObject:@[item]
                           afterDelay:0.0];
                return item;
            }
            
            if (![item isDownloading]) {
                if ([item hasValidContentLength] && !item.canMapData) {
                    // Perhaps the item just can not be mapped.
                    
                    [item performSelector:@selector(signalItemsDidFinish:)
                               withObject:@[item]
                               afterDelay:0.0];
                    
                    return item;
                }
                
                // nobody is downloading, but we got the item from the cachestore.
                // Something is wrong -> fail
                [item performSelector:@selector(signalItemsDidFail:)
                           withObject:@[item]
                           afterDelay:0.0];
                
                return nil;
            }
        }
        
        item.isRevalidating = revalidateCacheEntry;
        
        // Register item so that signalling works (even with fresh items
        // from the cache).
        [self registerClientItem:item];
        
        // Check if item is fully loaded already
        if (item.canMapData && !item.data && ![item hasValidContentLength]) {
            [self handleDownloadItem:item ignoreQueue:shouldIgnoreQueue];
            return item;
        }
        
        // Item is fresh, so call didLoad selector and return the cached item.
        if ([item isFresh] || neverRevalidate) {
            
            item.cacheStatus = kCacheStatusFresh;
#ifdef RESUMEABLE_DOWNLOAD
            if(item.currentContentLength < item.info.contentLength) {
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
        else {
            //#ifndef RESUMEABLE_DOWNLOAD
            // reset data, because there may be old data set already
            item.data = nil;//will cause the data to be relaoded from file when accessed next time
            //#endif
            
            // save information that object was in cache and has to be revalidated
            item.cacheStatus = kCacheStatusRevalidationPending;
            
            NSMutableURLRequest *IMSRequest = [NSMutableURLRequest requestWithURL:internalURL
                                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                  timeoutInterval:self.networkTimeoutIntervals.IMSRequest];
            
            NSDate *lastModified = [NSDate dateWithTimeIntervalSinceReferenceDate: [item.info.lastModified timeIntervalSinceReferenceDate]];
            [IMSRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
            [IMSRequest setValue:@"" forHTTPHeaderField:AFCacheInternalRequestHeader];
            
            if (item.info.eTag) {
                [IMSRequest addValue:item.info.eTag forHTTPHeaderField:kHTTPHeaderIfNoneMatch];
            }
            else {
                NSDate *lastModified = [NSDate dateWithTimeIntervalSinceReferenceDate:
                                        [item.info.lastModified timeIntervalSinceReferenceDate]];
                [IMSRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
            }
            
            item.IMSRequest = IMSRequest;
            ASSERT_NO_CONNECTION_WHEN_OFFLINE_FOR_URL(IMSRequest.URL);
            
            [self handleDownloadItem:item ignoreQueue:shouldIgnoreQueue];
        }
    }
    
    return item;
}

#pragma mark - Deprecated methods for getting cached items

// DO NOT USE THIS METHOD - it is deprecated
- (AFCacheableItem *)cachedObjectForURL:(NSURL *)url delegate: (id) aDelegate {
	return [self cachedObjectForURL: url delegate: aDelegate options: 0];
}

// DO NOT USE THIS METHOD - it is deprecated
- (AFCacheableItem *)cachedObjectForRequest:(NSURLRequest *)aRequest delegate: (id) aDelegate {
	return [self cachedObjectForURL: aRequest.URL
                           delegate: aDelegate
                           selector: @selector(connectionDidFinish:)
					didFailSelector: @selector(connectionDidFail:)
                            options: 0
                           userData: nil
						   username: nil password: nil request:aRequest];
}

// DO NOT USE THIS METHOD - it is deprecated
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

// DO NOT USE THIS METHOD - it is deprecated
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

// DO NOT USE THIS METHOD - it is deprecated
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


// DO NOT USE THIS METHOD - it is deprecated
- (AFCacheableItem *)cachedObjectForURL:(NSURL *)url delegate:(id) aDelegate selector:(SEL)aSelector didFailSelector:(SEL)didFailSelector options: (int) options {
	return [self cachedObjectForURL:url delegate:aDelegate selector:aSelector didFailSelector:didFailSelector options:options userData:nil username:nil password:nil request:nil];
}

/*
 * Performs an asynchroneous request and calls delegate when finished loading
 *
 */

// DO NOT USE THIS METHOD - it is deprecated
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

// DO NOT USE THIS METHOD - it is deprecated
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
    // to provide backward compability we convert this call to our new API
    
    AFRequestConfiguration *requestConfiguration = [[AFRequestConfiguration alloc] init];
    requestConfiguration.options = options;
    requestConfiguration.request = aRequest;
    requestConfiguration.userData = userData;
    
    NSURLCredential *urlCredential;
    if (aUsername && aPassword) {
        urlCredential = [NSURLCredential credentialWithUser:aUsername password:aPassword persistence:NSURLCredentialPersistenceForSession];
    }
    
    id completionBlock = aCompletionBlock;
    if (!completionBlock) {
        completionBlock = ^(AFCacheableItem *item) {
            // deprecated stuff
            [aDelegate performSelector:aSelector withObject:item];
        };
    }
    
    id failBlock = aFailBlock;
    if (!failBlock) {
        failBlock = ^(AFCacheableItem *item) {
            // deprecated stuff
            [aDelegate performSelector:aFailSelector withObject:item];
        };
    }

    // the progress (as selector) is implicitly done in AFCacheableItem:
    // - (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)receivedData
    id progressBlock = aProgressBlock;
    
    // delegate to our internal method
    return [self _internalCacheItemForURL:url
                            urlCredential:urlCredential
                          completionBlock:completionBlock
                                failBlock:failBlock
                            progressBlock:progressBlock
                     requestConfiguration:requestConfiguration];
}

#pragma mark - synchronous request methods

/*
 * performs a synchroneous request
 *
 */

- (AFCacheableItem *)cachedObjectForURLSynchronous: (NSURL *) url {
	return [self cachedObjectForURLSynchronous:url options:0];
}

- (AFCacheableItem *)cachedObjectForURLSynchronous:(NSURL *)url
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

#pragma mark - State (de-)serialization

- (void)serializeState {
    [self.archiveTimer invalidate];
    self.wantsToArchive = NO;
    [self serializeState:[self stateDictionary]];
}

- (NSDictionary*)stateDictionary {
    return [NSDictionary
            dictionaryWithObjects:@[self.cachedItemInfos, self.urlRedirects, self.packageInfos]
                          forKeys:@[kAFCacheInfoStoreCachedObjectsKey, kAFCacheInfoStoreRedirectsKey, kAFCacheInfoStorePackageInfosKey]];
}

- (void)serializeState:(NSDictionary*)state {
    @autoreleasepool {
#if AFCACHE_LOGGING_ENABLED
		AFLog(@"start archiving");
		CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
#endif
        @synchronized(self)
        {
            @autoreleasepool {
                
                if (self.totalRequestsForSession % kHousekeepingInterval == 0) [self doHousekeeping];
                NSString *filename = [self.dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
                NSDictionary *infoStore = [NSDictionary
                        dictionaryWithObjects:@[[state objectForKey:kAFCacheInfoStoreCachedObjectsKey], [state objectForKey:kAFCacheInfoStoreRedirectsKey]]
                                      forKeys:@[kAFCacheInfoStoreCachedObjectsKey, kAFCacheInfoStoreRedirectsKey]];
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
                
                filename = [self.dataPath stringByAppendingPathComponent: kAFCachePackageInfoDictionaryFilename];
                NSDictionary *packageInfos = [state valueForKey:kAFCacheInfoStorePackageInfosKey];
                serializedData = [NSKeyedArchiver archivedDataWithRootObject:packageInfos];
                if (serializedData)
                {
                    NSError* error = nil;
                    if (![serializedData writeToFile:filename options:NSDataWritingAtomic error:&error])
                    {
                        NSLog(@"Error: Could not write package infos to file '%@': Error = %@, infoStore = %@", filename, error, self.packageInfos);
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

- (void)deserializeState {
    // Deserialize cacheable item info store
    NSString *infoStoreFilename = [_dataPath stringByAppendingPathComponent:kAFCacheExpireInfoDictionaryFilename];
    NSDictionary *archivedExpireDates = [NSKeyedUnarchiver unarchiveObjectWithFile: infoStoreFilename];
    NSMutableDictionary *cacheItemInfos = [archivedExpireDates objectForKey:kAFCacheInfoStoreCachedObjectsKey];
    NSMutableDictionary *urlRedirects = [archivedExpireDates objectForKey:kAFCacheInfoStoreRedirectsKey];
    if (cacheItemInfos && urlRedirects) {
        _cachedItemInfos = [NSMutableDictionary dictionaryWithDictionary: cacheItemInfos];
        _urlRedirects = [NSMutableDictionary dictionaryWithDictionary: urlRedirects];
        AFLog(@ "Successfully unarchived expires dictionary");
    } else {
        _urlRedirects = [NSMutableDictionary dictionary];
        _cachedItemInfos = [NSMutableDictionary dictionary];
        AFLog(@ "Created new expires dictionary");
    }

    // Deserialize package infos
    NSString *packageInfoPlistFilename = [_dataPath stringByAppendingPathComponent:kAFCachePackageInfoDictionaryFilename];
    NSDictionary *archivedPackageInfos = [NSKeyedUnarchiver unarchiveObjectWithFile: packageInfoPlistFilename];
    if (archivedPackageInfos) {
        _packageInfos = [NSMutableDictionary dictionaryWithDictionary: archivedPackageInfos];
        AFLog(@ "Successfully unarchived package infos dictionary");
    }
    else {
        _packageInfos = [[NSMutableDictionary alloc] init];
        AFLog(@ "Created new package infos dictionary");
    }
}

- (void)startArchiveThread:(NSTimer*)timer {
    self.wantsToArchive = NO;
    NSMutableDictionary* state = [NSMutableDictionary dictionaryWithDictionary: [self stateDictionary]];

    // Copy state items as they shall not be altered when state is persisted
    // TODO: This copy code must be synchronized with state modifications
    for (id key in [state allKeys]) {
        NSObject *stateItem = [state objectForKey:key];
        [state setObject:[stateItem copy] forKey:key];
    }

    [NSThread detachNewThreadSelector:@selector(serializeState:)
                             toTarget:self
                           withObject:state];
}

- (void)archive {
    [self.archiveTimer invalidate];
    if (self.archiveInterval > 0) {
        self.archiveTimer = [NSTimer scheduledTimerWithTimeInterval:[self archiveInterval]
														target:self
													  selector:@selector(startArchiveThread:)
													  userInfo:nil
													   repeats:NO];
    }
    self.wantsToArchive = YES;
}

- (void)archiveNow {
    [self.archiveTimer invalidate];
    [self startArchiveThread:nil];
    [self archive];
}

/* removes every file in the cache directory */
- (void)invalidateAll {
	NSError *error;
	
	/* remove the cache directory and its contents */
	if (![[NSFileManager defaultManager] removeItemAtPath: self.dataPath error: &error]) {
		NSLog(@ "Failed to remove cache contents at path: %@", self.dataPath);
		//return; If there was no old directory we for sure want a new one...
	}
	
	/* create a new cache directory */
	if (![[NSFileManager defaultManager] createDirectoryAtPath: self.dataPath
								   withIntermediateDirectories: NO
													attributes: nil
														 error: &error]) {
		NSLog(@ "Failed to create new cache directory at path: %@", self.dataPath);
		return; // this is serious. we need this directory.
	}
	self.cachedItemInfos = [NSMutableDictionary dictionary];
    self.urlRedirects = [NSMutableDictionary dictionary];
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
	return [self.dataPath stringByAppendingPathComponent: filename];
}

- (NSString *)filePath:(NSString *)filename pathExtension:(NSString *)pathExtension
{
    if (!pathExtension) {
        return [self filePath:filename];
    }
    else {
        return [[self.dataPath stringByAppendingPathComponent:filename] stringByAppendingPathExtension:pathExtension];
    }
}

- (NSString *)filePathForURL: (NSURL *) url {
	return [self.dataPath stringByAppendingPathComponent: [self filenameForURL: url]];
}

- (NSString *)fullPathForCacheableItem:(AFCacheableItem*)item {
	
    if (item == nil) return nil;
    
    NSString *fullPath = nil;
    
    if (!self.cacheWithHashname)
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

- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL)fileOnly
{
    [self removeCacheEntry:info fileOnly:fileOnly fallbackURL:nil];
}

- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL) fileOnly fallbackURL:(NSURL *)fallbackURL;
{
    if (!info) {
        return;
    }
	// remove redirects to this entry
	for (id redirectKey in [self.urlRedirects allValues]) {
		if ([redirectKey isKindOfClass:[NSString class]]) {
			id redirectTarget = [self.urlRedirects objectForKey:redirectKey];
			if ([redirectTarget isKindOfClass:[NSString class]]) {
				if([redirectTarget isEqualToString:[info.request.URL absoluteString]])
				{
					[self.urlRedirects removeObjectForKey:redirectKey];
				}
			}
			
		}
	}
	
	NSError *error;
    
    NSString *filePath = nil;
    if (!self.cacheWithHashname)
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
		if (!fileOnly) {
            if (fallbackURL) {
                [self.cachedItemInfos removeObjectForKey:[fallbackURL absoluteString]];
            }
            else {
                [self.cachedItemInfos removeObjectForKey:[[info.request URL] absoluteString]];
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
	
	if (![[NSFileManager defaultManager] setAttributes: dict ofItemAtPath: filePath error: &error]) {
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
	if (![[NSFileManager defaultManager] fileExistsAtPath:pathToDirectory isDirectory:&isDirectory] || !isDirectory)
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
	if (self.maxItemFileSize == kAFCacheInfiniteFileSize || cacheableItem.info.contentLength < self.maxItemFileSize) {
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
		NSLog(@ "AFCache: item %@ \nsize exceeds maxItemFileSize (%f). Won't write file to disk",cacheableItem.url, self.maxItemFileSize);
		[self.cachedItemInfos removeObjectForKey: [cacheableItem.url absoluteString]];
	}
    
    return fileHandle;
}

- (BOOL)_fileExistsOrPendingForCacheableItem:(AFCacheableItem*)item {
    if (![self isValidRequestURL:item.url]) {
        return NO;
    }
    
	// the complete path
	NSString *filePath = [self fullPathForCacheableItem:item];
    
	AFLog(@"checking for file at path %@", filePath);
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: filePath])
    {
        // file doesn't exist. check if someone else is downloading the url already
        if ([self.pendingConnections objectForKey:item.url] != nil || [self isQueuedURL:item.url])
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
    if (![self isValidRequestURL:URL]) {
        return nil;
    }
    
	if ([[URL absoluteString] hasPrefix:@"data:"]) {
        return nil;
	}
    
    // the URL we use to lookup in the cache, may be changed to redirected URL
    NSURL *lookupURL = URL;
    
    // the returned cached object
    AFCacheableItem *cacheableItem = nil;
	
    
    AFCacheableItemInfo *info = [self.cachedItemInfos objectForKey: [lookupURL absoluteString]];
    if (info == nil) {
        NSString *redirectURLString = [self.urlRedirects valueForKey:[URL absoluteString]];
        info = [self.cachedItemInfos objectForKey: redirectURLString];
    }
    
    if (info != nil) {
        AFLog(@"Cache hit for URL: %@", [URL absoluteString]);
		
        // check if there is an item in pendingConnections
        cacheableItem = [self.pendingConnections objectForKey:URL];
        if (!cacheableItem) {
            cacheableItem = [[AFCacheableItem alloc] init];
            cacheableItem.cache = self;
            cacheableItem.url = URL;
            cacheableItem.info = info;
            cacheableItem.currentContentLength = 0;//info.contentLength;
            
            if (!self.cacheWithHashname)
            {
                cacheableItem.info.filename = [self filenameForURL:cacheableItem.url];
            }
            
            // check if file is valid
            BOOL fileExists = [self _fileExistsOrPendingForCacheableItem:cacheableItem];
            if (!fileExists) {
                // Something went wrong
                AFLog(@"Cache info store out of sync for url %@, removing cached file %@.", [URL absoluteString], [self fullPathForCacheableItem:cacheableItem]);
                [self removeCacheEntry:cacheableItem.info fileOnly:YES];
                cacheableItem = nil;
            }
			else
			{
				//make sure that we continue downloading by setting the length (currently done by reading out file lenth in the info.actualLength accessor)
				cacheableItem.info.cachePath = [self fullPathForCacheableItem:cacheableItem];
			}
        }
        if ([self isOffline]) {
            cacheableItem.cacheStatus = kCacheStatusFresh;
        }
        else {
            [cacheableItem validateCacheStatus];
        }
    }
    
    return cacheableItem;
}

#pragma mark - Cancel requests on cache

- (void)cancelConnectionsForURL: (NSURL *) url
{
	if (url)
	{
        AFCacheableItem *pendingItem = [self.pendingConnections objectForKey: url];
		AFLog(@"Cancelling connection for URL: %@", [url absoluteString]);
        pendingItem.delegate = nil;
        pendingItem.completionBlock = nil;
        pendingItem.failBlock = nil;
        pendingItem.progressBlock = nil;
		[pendingItem.connection cancel];
		[self.pendingConnections removeObjectForKey: url];
	}
}

- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)itemDelegate
{
    if (url)
    {
        [self cancelConnectionsForURL:url];
		
        [self removeClientItemForURL:url itemDelegate:itemDelegate];
    }
}

- (void)cancelAsynchronousOperationsForDelegate:(id)itemDelegate
{
    if (itemDelegate)
    {
        NSArray *allKeys = [self.clientItems allKeys];
		for (NSURL *url in allKeys)
        {
            NSMutableArray* const clientItemsForURL = [self.clientItems objectForKey:url];
            
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
                        [self.clientItems removeObjectForKey:url];
                    }
                }
            }
        }
		
		[self fillPendingConnections];
    }
}

- (void)cancelPendingConnections
{
    for (AFCacheableItem* pendingItem in [self.pendingConnections allValues])
    {
        [pendingItem.connection cancel];
    }
    [self.pendingConnections removeAllObjects];
}

- (void)cancelAllClientItems
{
    [self cancelPendingConnections];
    
    for (NSArray* items in [self.clientItems allValues])
    {
        for (AFCacheableItem* item in items)
        {
            item.delegate = nil;
            item.completionBlock = nil;
            item.failBlock = nil;
            item.progressBlock = nil;
        }
    }
    
    [self.clientItems removeAllObjects];
}

#pragma mark

- (void)removeReferenceToConnection: (NSURLConnection *) connection {
    NSArray *pendingItems = [NSArray arrayWithArray:[self.pendingConnections allValues]];
    for (AFCacheableItem *item in pendingItems) {
        if (item.connection == connection) {
            [self.pendingConnections removeObjectForKey:item.url];
        }
    }
}

- (void)registerClientItem:(AFCacheableItem*)itemToRegister
{
    NSURL *URLKey = itemToRegister.url;
    NSMutableArray* existingClientItems = [self.clientItems objectForKey:URLKey];
    if (!existingClientItems) {
        existingClientItems = [NSMutableArray array];
        [self.clientItems setObject:existingClientItems forKey:URLKey];
    }
    [existingClientItems addObject:itemToRegister];
}

- (NSArray*)clientItemsForURL:(NSURL*)url
{
    return [[self.clientItems objectForKey:url] copy];
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
    NSArray* items = [self.clientItems objectForKey:url];
    [self.downloadQueue removeObjectsInArray:items];
	[self.clientItems removeObjectForKey:url];
}


- (void)removeClientItemForURL:(NSURL*)url itemDelegate:(id)itemDelegate
{
	NSMutableArray* const clientItemsForURL = [self.clientItems objectForKey:url];
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
				[self.clientItems removeObjectForKey:url];
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

/**
 * Add the item to the downloadQueue
 */
- (void)addItemToDownloadQueue:(AFCacheableItem*)item
{
    if (!self.downloadPermission) {
        if (item.failBlock) {
            item.failBlock(item);
        }
        return;
    }
    
	if ((item != nil) && ![item isDownloading])
	{
		[self.downloadQueue addObject:item];
		if ([[self.pendingConnections allKeys] count] < self.concurrentConnections)
		{
			[self downloadItem:item];
		}
	}
}

- (void)removeFromDownloadQueue:(AFCacheableItem*)item
{
	if (item != nil && [self.downloadQueue containsObject:item])
	{
		// TODO: if there are more delegates on an item, then do not remove the whole item, just set the corrensponding delegate to nil and let the item there for remaining delegates
		[self.downloadQueue removeObject:item];
	}
}

- (void)flushDownloadQueue
{
	for (AFCacheableItem *item in [self.downloadQueue copy])
	{
		[self downloadNextEnqueuedItem];
	}
}

- (void)fillPendingConnections
{
	for (int i = 0; i < self.concurrentConnections; i++)
	{
		if ([[self.pendingConnections allKeys] count] < self.concurrentConnections)
		{
			[self downloadNextEnqueuedItem];
		}
	}
}

- (void)downloadNextEnqueuedItem
{
	if ([self.downloadQueue count] > 0)
	{
		AFCacheableItem *nextItem = [self.downloadQueue objectAtIndex:0];
		[self downloadItem:nextItem];
	}
}

- (BOOL)isQueuedURL:(NSURL*)url
{
	
	for (AFCacheableItem *item in self.downloadQueue)
	{
		if ([[url absoluteString] isEqualToString:[item.url absoluteString]])
		{
			return YES;
		}
	}
	
	return NO;
}

- (void)prioritizeURL:(NSURL*)url
{
    // find the item that is actually downloading and put it into the pole position
    for (AFCacheableItem* cacheableItem in [self clientItemsForURL:url])
    {
        if ([self.downloadQueue containsObject:cacheableItem])
        {
            [self.downloadQueue removeObject:cacheableItem];
            [self.downloadQueue insertObject:cacheableItem atIndex:0];
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
	if (self.downloadPaused)
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
    [self.downloadQueue removeObject:item];

    // check if we are downloading already
    if ([self.pendingConnections objectForKey:item.url])
    {
        // don't start another connection
        AFLog(@"We are downloading already. Won't start another connection for %@", item.url);
        return;
    }
    
	NSTimeInterval timeout = item.isPackageArchive ? self.networkTimeoutIntervals.PackageRequest : self.networkTimeoutIntervals.GETRequest;
	
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
    [self.pendingConnections setObject: item forKey: item.url];
    
}

- (BOOL)hasCachedItemForURL:(NSURL *)url
{
    AFCacheableItem* item = [self cacheableItemFromCacheStore:url];
    if (item)
    {
        return nil != item.data;
    }
    
    return NO;
}

#pragma mark - offline & pause methods

- (void)setDownloadPaused:(BOOL)pause
{
	_downloadPaused = pause;
    [self.packageArchiveQueue setSuspended:pause];
	
	if (pause)
	{
		// Check for running connection -> add the items to the queue again
        NSMutableArray* allItems = [NSMutableArray array];
		for (NSURL* url in [self.pendingConnections allKeys])
		{
            [allItems addObjectsFromArray:[self.clientItems objectForKey:url]];
        }
        
        [self cancelPendingConnections];
        
        for (AFCacheableItem* item in allItems)
        {
            if (![self.downloadQueue containsObject:item])
            {
                [self.downloadQueue insertObject:item atIndex:0];   // retain count +1 because we are removing it from clientItems afterwards (which decreases the retain count again)
            }
        }
	}
	else {
		// Resume downloading
		for (int i = 0; i < self.concurrentConnections; i++)
		{
			if ([[self.pendingConnections allKeys] count] < self.concurrentConnections)
			{
				[self downloadNextEnqueuedItem];
			}
		}
		
	}
    
}

- (BOOL)isOffline {
	return /*![self isConnectedToNetwork] || */ _offline || !self.downloadPermission;
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
    if (_connectedToNetwork != connected)
    {
        [self willChangeValueForKey:@"connectedToNetwork"];
        _connectedToNetwork = connected;
        [self didChangeValueForKey:@"connectedToNetwork"];
    }
}

#pragma mark - Helper

/**
 * @return is that url valid to be requested
 */
- (BOOL)isValidRequestURL:(NSURL*)url
{
    // url should not be nil nor having a zero length
    return [[url absoluteString] length] > 0;
}

/**
 *
 */
- (void)handleInvalidURLRequest:(AFCacheableItemBlock)failBlock
{
    NSError *error = [NSError errorWithDomain:@"URL is not set" code:-1 userInfo:nil];
    
    AFCacheableItem *item = [[AFCacheableItem alloc] init];
    item.error = error;
    
    if (failBlock) {
        failBlock(item);
    }
}

@end

#pragma mark - additional implementations

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
                                     didFailSelector: nil
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

-(BOOL)persistDownloadQueue
{
	return [self.downloadQueue writeToFile:@"downloadQueueStore" atomically:YES];
}

@end
