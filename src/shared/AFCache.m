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
#import <MacTypes.h>
#import "AFRegexString.h"
#import "AFCache_Logging.h"
#import "AFDownloadOperation.h"
#import "AFCacheableItem+FileAttributes.h"

#import <VersionIntrospection/VersionIntrospection.h>

#if USE_ASSERTS
#define ASSERT_NO_CONNECTION_WHEN_IN_OFFLINE_MODE_FOR_URL(url) NSAssert( [(url) isFileURL] || [self offlineMode] == NO, @"No connection should be opened if we're in offline mode - this seems like a bug")
#else
#define ASSERT_NO_CONNECTION_WHEN_IN_OFFLINE_MODE_FOR_URL(url) do{}while(0)
#endif

const double kAFCacheInfiniteFileSize = 0.0;
const double kAFCacheArchiveDelay = 30.0; // archive every 30s

extern NSString* const UIApplicationWillResignActiveNotification;

@interface AFCache()

@property (nonatomic, copy) NSString *context;
@property (nonatomic, strong) NSTimer *archiveTimer;
@property (nonatomic, assign) BOOL wantsToArchive;
@property (nonatomic, assign) BOOL connectedToNetwork;
@property (nonatomic, strong) NSOperationQueue *packageArchiveQueue;
@property (nonatomic, strong) NSOperationQueue *downloadOperationQueue;
@property (nonatomic, strong) NSString* version;
@property (nonatomic, assign, readonly) NSString* infoDictionaryPath;
@property (nonatomic, assign, readonly) NSString* metaDataDictionaryPath;
@property (nonatomic, assign, readonly) NSString* expireInfoDictionaryPath;

@end

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;
static NSMutableDictionary* AFCache_contextCache = nil;

#pragma mark singleton methods

+ (AFCache *)sharedInstance {
    @synchronized(self) {
        if (!sharedAFCacheInstance) {
            sharedAFCacheInstance = [[self alloc] initWithContext:nil];
            sharedAFCacheInstance.diskCacheDisplacementTresholdSize = kDefaultDiskCacheDisplacementTresholdSize;
        }
    }
    return sharedAFCacheInstance;
}

#pragma mark init methods

- (id)initWithContext:(NSString*)context {
    if (!context && sharedAFCacheInstance) {
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
    _offlineMode = NO;
    _wantsToArchive = NO;
    _connectedToNetwork = NO;
    _archiveInterval = kAFCacheArchiveDelay;
    _failOnStatusCodeAbove400 = YES;
    _cacheWithHashname = YES;
    _maxItemFileSize = kAFCacheInfiniteFileSize;
    _networkTimeoutIntervals.IMSRequest = kDefaultNetworkTimeoutIntervalIMSRequest;
    _networkTimeoutIntervals.GETRequest = kDefaultNetworkTimeoutIntervalGETRequest;
    _networkTimeoutIntervals.PackageRequest = kDefaultNetworkTimeoutIntervalPackageRequest;
    _totalRequestsForSession = 0;
    _packageArchiveQueue = [[NSOperationQueue alloc] init];
    [_packageArchiveQueue setMaxConcurrentOperationCount:1];

    _downloadOperationQueue = [[NSOperationQueue alloc] init];
    [_downloadOperationQueue setMaxConcurrentOperationCount:kAFCacheDefaultConcurrentConnections];

    if (!_dataPath)
    {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *appId = [@"afcache" stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
        _dataPath = [[[paths objectAtIndex: 0] stringByAppendingPathComponent: appId] copy];
    }
    
    [self deserializeState];

    /* check for existence of cache directory */
    if ([[NSFileManager defaultManager] fileExistsAtPath:_dataPath]) {
        AFLog(@ "Successfully unarchived cache store");
    }
    else {
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:_dataPath
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            AFLog(@ "Failed to create cache directory at path %@: %@", _dataPath, [error description]);
        }
        else
        {
            NSString *dataPath = _dataPath;
            if ([[dataPath pathComponents] containsObject:@"Library"])
            {
                while (![[dataPath lastPathComponent] isEqualToString:@"Library"] && ![[dataPath lastPathComponent] isEqualToString:@"Caches"]) {
                    [AFCache addSkipBackupAttributeToItemAtURL:[NSURL fileURLWithPath:dataPath]];
                    dataPath = [dataPath stringByDeletingLastPathComponent];
                }
            }
        }
    }

    [AFCache addSkipBackupAttributeToItemAtURL:[NSURL fileURLWithPath:_dataPath]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_context)
    {
        [AFCache_contextCache removeObjectForKey:_context];
    }
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

- (int)concurrentConnections {
    return [self.downloadOperationQueue maxConcurrentOperationCount];
}

- (void)setConcurrentConnections:(int)maxConcurrentConnections {
    [self.downloadOperationQueue setMaxConcurrentOperationCount:maxConcurrentConnections];
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
    [self cancelAllDownloads];

    [self initialize];
}


+(BOOL)addSkipBackupAttributeToItemAtURL:(NSURL *)URL
{
#if TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1 || TARGET_OS_MAC && MAC_OS_X_VERSION_MIN_ALLOWED < MAC_OS_X_VERSION_10_8
    if (![[NSFileManager defaultManager] fileExistsAtPath:[URL path]]) {
        return NO;
    }
    
    NSError *error = nil;
    BOOL success = [URL setResourceValue:[NSNumber numberWithBool:YES] forKey: NSURLIsExcludedFromBackupKey error:&error];
    if (!success) {
        NSLog(@"Error excluding %@ from backup: %@", [URL lastPathComponent], error);
    }
	return success;
#else
    NSLog(@"ERROR: System does not support excluding files from backup");
    return NO;
#endif
}

// remove all cache entries are not in a given set
- (void)doHousekeepingWithRequiredCacheItemURLs:(NSSet*)requiredURLs
{
    NSMutableSet* fileNames = [NSMutableSet set];
    
    NSMutableDictionary* cacheInfoForFileName = [NSMutableDictionary dictionary];
    for (NSURL* cacheURL in requiredURLs) {
        AFCacheableItem* item = [self cacheableItemFromCacheStore:cacheURL];
        if (item.info) {
            NSString* fileName = item.info.filename;
            [fileNames addObject:fileName];
            [cacheInfoForFileName setObject:item.info forKey:fileName];
        }

    }
    [fileNames addObject:kAFCachePackageInfoDictionaryFilename];
    [fileNames addObject:kAFCacheMetadataFilename];
    [fileNames addObject:kAFCacheExpireInfoDictionaryFilename];
    NSSet* fileNameSet = [NSSet setWithSet:fileNames];
    __block NSMutableArray* urlsToRemove = [NSMutableArray array];
    [self performBlockOnAllCacheFiles:^(NSURL *url) {
        NSError *error;
        NSNumber *isDirectory = nil;
        if (! [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error]) {
            NSLog(@"ERROR: cleanup encountered error: %@", error);
        }
        else if (! [isDirectory boolValue]) {
            NSString* fileName = [url lastPathComponent];
            if(![fileNameSet containsObject:[fileName stringByDeletingPathExtension]])
            {
                [urlsToRemove addObject:url];
            }
        }
    }];
    for (NSURL* url in urlsToRemove) {
        [self removeCacheEntryAndFileForFileURL:url];
    }
}
-(void)performBlockOnAllCacheFiles:(void (^)(NSURL* url))cacheItemActionBlock
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *directoryURL = [NSURL fileURLWithPath:self.dataPath];
    
    NSDirectoryEnumerator *enumerator = [fileManager
                                         enumeratorAtURL:directoryURL
                                         includingPropertiesForKeys:nil
                                         options:0
                                         errorHandler:^(NSURL *url, NSError *error) {
                                             NSLog(@"ERROR: encountered error while processing all cache files: %@", error);
                                             return YES;
                                         }];
    
    for (NSURL *url in enumerator) {
        cacheItemActionBlock(url);
    }
}
// remove all expired cache entries
// TODO: exchange with a better displacement strategy
- (void)doHousekeeping {
    if ([self offlineMode]) return; // don't cleanup if we're in offline mode
	unsigned long size = [self diskCacheSize];
	if (size < self.diskCacheDisplacementTresholdSize) return;
	NSDate *now = [NSDate date];
	NSArray *keys = nil;
	NSString *key = nil;
	for (AFCacheableItemInfo *info in [self.cachedItemInfos allValues]) {
		if (info.expireDate && info.expireDate == [now earlierDate:info.expireDate]) {
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
    NSLog(@"TODO: Implement me or remove me (I am called in doHousekeeping)");
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

    if ([url isFileURL]) {
        AFCacheableItem *shortCircuitItem = [[AFCacheableItem alloc] init];
        shortCircuitItem.url = url;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[url path]]) {
            shortCircuitItem.data = [NSData dataWithContentsOfURL: url];
            if (completionBlock) {
                completionBlock(shortCircuitItem);
            }
        }
        else {
            if (failBlock) {
                failBlock(shortCircuitItem);
            }
        }
        
        return shortCircuitItem;
    }
    
    // increase count of request in this session
	_totalRequestsForSession++;
    
    // extract option-parts from requestConfiguration.options
    BOOL invalidateCacheEntry = (requestConfiguration.options & kAFCacheInvalidateEntry) != 0;
    BOOL revalidateCacheEntry = (requestConfiguration.options & kAFCacheRevalidateEntry) != 0;
    BOOL justFetchHTTPHeader = (requestConfiguration.options & kAFCacheJustFetchHTTPHeader) != 0;
    BOOL isPackageArchive = (requestConfiguration.options & kAFCacheIsPackageArchive) != 0;
    BOOL neverRevalidate = (requestConfiguration.options & kAFCacheNeverRevalidate) != 0;
    BOOL returnFileBeforeRevalidation = (requestConfiguration.options & kAFCacheReturnFileBeforeRevalidation) != 0;

	// Update URL with redirected URL if in offline mode
    BOOL didRewriteURL = NO; // the request URL might be rewritten by the cache internally when we're in offline mode
    url = [self urlOrRedirectURLInOfflineModeForURL:url redirected:&didRewriteURL];

    // try to get object from disk
    AFCacheableItem *item = nil;
    if (!invalidateCacheEntry) {
        item = [self cacheableItemFromCacheForURL:url];
    }
    
    BOOL performGETRequest = NO; // will be set to YES if we're online and have a cache miss
    
    if (!item) {
        // if we are in offline mode and do not have a cached version, so return nil
        if (!url.isFileURL && [self offlineMode]) {
            if (failBlock) {
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
    item.url = url;
    item.userData = requestConfiguration.userData;
    item.urlCredential = urlCredential;
    item.justFetchHTTPHeader = justFetchHTTPHeader;
    item.isPackageArchive = isPackageArchive;
    item.URLInternallyRewritten = didRewriteURL;
    item.servedFromCache = !performGETRequest;
    item.info.request = requestConfiguration.request;
    item.hasReturnedCachedItemBeforeRevalidation = NO;

    if (!self.cacheWithHashname) {
        item.info.filename = [self filenameForURL:item.url];
    }
    
    [item addCompletionBlock:completionBlock failBlock:failBlock progressBlock:progressBlock];

    if (performGETRequest) {
        // TODO: Why do we cache the item here? Nothing has been downloaded yet?
        [self.cachedItemInfos setObject:item.info forKey:[url absoluteString]];
        
        [self addItemToDownloadQueue:item];
        return item;
    }
    else
    {
        // object found in cache.
        // now check if it is fresh enough to serve it from disk.
        // pretend it's fresh when cache is in offline mode
        item.servedFromCache = YES;
        
        if (![self isConnectedToNetwork] || ([self offlineMode] && !revalidateCacheEntry)) {
            // return item and call delegate only if fully loaded
            if (item.data) {
                if (completionBlock) {
                    completionBlock(item);
                }
                return item;
            }
            
            if (![self isQueuedOrDownloadingURL:item.url]) {
                if ([item hasValidContentLength] && !item.canMapData) {
                    // Perhaps the item just can not be mapped.
                    if (completionBlock) {
                        completionBlock(item);
                    }
                    return item;
                }
                
                // nobody is downloading, but we got the item from the cachestore.
                // Something is wrong -> fail
                if (failBlock) {
                    failBlock(item);
                }
                return nil;
            }
        }
        
        item.isRevalidating = revalidateCacheEntry;
        
        // Check if item is fully loaded already
        if (item.canMapData && !item.data && ![item hasValidContentLength]) {
            [self addItemToDownloadQueue:item];
            return item;
        }
        
        // Item is fresh, so call didLoad selector and return the cached item.
        if ([item isFresh] || returnFileBeforeRevalidation || neverRevalidate) {
            item.cacheStatus = kCacheStatusFresh;
#ifdef RESUMEABLE_DOWNLOAD
            if(item.currentContentLength < item.info.contentLength) {
                //resume download
                item.cacheStatus = kCacheStatusDownloading;
                [self handleDownloadItem:item ignoreQueue:shouldIgnoreQueue];
            }
#else
            item.currentContentLength = item.info.contentLength;
            if (completionBlock) {
                completionBlock(item);
            }
            AFLog(@"serving from cache: %@", item.url);
#endif
            if (returnFileBeforeRevalidation) {
                item.hasReturnedCachedItemBeforeRevalidation = YES;
            } else {
                return item;
            }
            //item.info.responseTimestamp = [NSDate timeIntervalSinceReferenceDate];
        }

        // Item is not fresh, fire an If-Modified-Since request
        //#ifndef RESUMEABLE_DOWNLOAD
        // reset data, because there may be old data set already
        item.data = nil;//will cause the data to be reloaded from file when accessed next time
        //#endif
        
        // save information that object was in cache and has to be revalidated
        item.cacheStatus = kCacheStatusRevalidationPending;
        
        NSMutableURLRequest *IMSRequest = [NSMutableURLRequest requestWithURL:url
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
            // TODO: Why do we overwrite the existing header field here already set above?
            [IMSRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
        }
        
        item.IMSRequest = IMSRequest;
        ASSERT_NO_CONNECTION_WHEN_IN_OFFLINE_MODE_FOR_URL(IMSRequest.URL);

        [self addItemToDownloadQueue:item];
    }
    
    return item;
}

- (AFCacheableItem *)cacheableItemFromCacheForURL:(NSURL *)url {
    AFCacheableItem *item = [self cacheableItemFromCacheStore:url];

    // check validity of cached item
    // TODO: (Claus Weymann:) validate this check (does this ensure that we continue downloading but also detect corrupt files?)
    if (![item isDataLoaded] && ([item hasDownloadFileAttribute] || ![item hasValidContentLength]) && ![self isDownloadingURL:url]) {
        //Claus Weymann: item is not vailid and not allready being downloaded, set item to nil to trigger download
        item = nil;
    }
    return item;
}

- (NSURL*)urlOrRedirectURLInOfflineModeForURL:(NSURL *)url redirected:(BOOL *)redirected {
    *redirected = NO;
    if ([self offlineMode]) {
        // In offline mode we change the request URL to the redirected URL (if any)
        // TODO: Michael Markowski has left this comment (I don't know if it still holds true):
        // AFAIU redirects of type 302 MUST NOT be cached
        // since we do not distinguish between 301 and 302 or other types of redirects, nor save the status code anywhere
        // we simply only check the cached redirects if we're in offline mode
        // see http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html 13.4 Response Cacheability
        NSString *redirectURL = [self.urlRedirects valueForKey:[url absoluteString]];
        if (redirectURL) {
            url = [NSURL URLWithString: redirectURL];
            *redirected = YES;
        }
    }
    return url;
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
    
    __weak id weakDelegate = aDelegate;
    
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
            [weakDelegate performSelector:aSelector withObject:item];
        };
    }
    
    id failBlock = aFailBlock;
    if (!failBlock) {
        failBlock = ^(AFCacheableItem *item) {
            // deprecated stuff
            [weakDelegate performSelector:aFailSelector withObject:item];
        };
    }

    // the progress (as selector) is implicitly done in AFCacheableItem:
    // - (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)receivedData
    id progressBlock = aProgressBlock;
    
    // delegate to our internal method
    AFCacheableItem *item = [self _internalCacheItemForURL:url
                                             urlCredential:urlCredential
                                           completionBlock:completionBlock
                                                 failBlock:failBlock
                                             progressBlock:progressBlock
                                      requestConfiguration:requestConfiguration];
    item.delegate = weakDelegate;
    return item;
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
	
    bool invalidateCacheEntry = (options & kAFCacheInvalidateEntry) != 0;
	AFCacheableItem *obj = nil;
	if (url) {
		// try to get object from disk if cache is enabled
		if (!invalidateCacheEntry) {
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
            
            ASSERT_NO_CONNECTION_WHEN_IN_OFFLINE_MODE_FOR_URL(url);
            
			NSData *data = [NSURLConnection sendSynchronousRequest: request returningResponse: &response error: &err];
			if ([response respondsToSelector: @selector(statusCode)]) {
				NSInteger statusCode = [( (NSHTTPURLResponse *)response )statusCode];
				if (statusCode != 200 && statusCode != 304) {
					return nil;
				}
			}
			// If request was successful there should be a cacheable item now.
			if (data) {
				obj = [self cacheableItemFromCacheStore: url];
			}
		}
	}
	return obj;
}

#pragma mark - URL cache state testing

- (BOOL)isQueuedOrDownloadingURL: (NSURL*)url {
    return ([self isQueuedURL:url] || [self isDownloadingURL:url]);
}

- (BOOL)isDownloadingURL:(NSURL *)url {
    return ([[self nonCancelledDownloadOperationForURL:url] isExecuting]);
}

- (AFDownloadOperation*)nonCancelledDownloadOperationForURL:(NSURL*)url {
    for (AFDownloadOperation *downloadOperation in [self.downloadOperationQueue operations]) {
        if (![downloadOperation isCancelled] && [[downloadOperation.cacheableItem.url absoluteString] isEqualToString:[url absoluteString]]) {
            return downloadOperation;
        }
    }
    return nil;
}

#pragma mark - State (de-)serialization

- (void)serializeState {
    @synchronized (self.archiveTimer) {
        [self.archiveTimer invalidate];
        self.wantsToArchive = NO;
        [self serializeState:[self stateDictionary]];
    }
}

- (NSDictionary*)stateDictionary {
    return @{kAFCacheInfoStoreCachedObjectsKey : self.cachedItemInfos,
            kAFCacheInfoStoreRedirectsKey : self.urlRedirects,
            kAFCacheInfoStorePackageInfosKey : self.packageInfos,
            kAFCacheVersionKey : self.version?:@"",
             };
}

//TODO: state dictionary bundles information about state but is not serialized (persisted) as such. it  splits into parts and serializes some of the information. why?
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
                
               NSDictionary *infoStore = @{
                        kAFCacheInfoStoreCachedObjectsKey : state[kAFCacheInfoStoreCachedObjectsKey],
                        kAFCacheInfoStoreRedirectsKey : state[kAFCacheInfoStoreRedirectsKey]};
                [self saveDictionary:infoStore ToFile:self.expireInfoDictionaryPath];
                
                NSDictionary* packageInfos = [state valueForKey:kAFCacheInfoStorePackageInfosKey];
                [self saveDictionary:packageInfos ToFile:self.infoDictionaryPath];
                
                NSDictionary* metaData = @{kAFCacheVersionKey:[state valueForKey:kAFCacheVersionKey]};
                [self saveDictionary:metaData ToFile:self.metaDataDictionaryPath];
            }
        }
#if AFCACHE_LOGGING_ENABLED
		AFLog(@"Finish archiving in %f", CFAbsoluteTimeGetCurrent() - start);
#endif
    }
}

-(void)saveDictionary:(NSDictionary*)dictionary ToFile:(NSString*)fileName
{
    NSData* serializedData = [NSKeyedArchiver archivedDataWithRootObject:dictionary];
    if (serializedData)
    {
        NSError* error = nil;
#if TARGET_OS_IPHONE
        NSDataWritingOptions options = NSDataWritingAtomic | NSDataWritingFileProtectionNone;
#else
        NSDataWritingOptions options = NSDataWritingAtomic;
#endif
        if (![serializedData writeToFile:fileName options:options error:&error])
        {
            NSLog(@"Error: Could not write dictionary to file '%@': Error = %@, infoStore = %@", fileName, error, dictionary);
        }
        [AFCache addSkipBackupAttributeToItemAtURL:[NSURL fileURLWithPath:fileName]];
    }
    else
    {
        NSLog(@"Error: Could not archive dictionary %@", dictionary);
    }
}

- (void)deserializeState {
    // Deserialize cacheable item info store
    NSDictionary *archivedExpireDates = [NSKeyedUnarchiver unarchiveObjectWithFile: self.expireInfoDictionaryPath];
    NSMutableDictionary *cachedItemInfos = [archivedExpireDates objectForKey:kAFCacheInfoStoreCachedObjectsKey];
    NSMutableDictionary *urlRedirects = [archivedExpireDates objectForKey:kAFCacheInfoStoreRedirectsKey];
    if (cachedItemInfos && urlRedirects) {
        _cachedItemInfos = [NSMutableDictionary dictionaryWithDictionary:cachedItemInfos];
        _urlRedirects = [NSMutableDictionary dictionaryWithDictionary: urlRedirects];
        AFLog(@ "Successfully unarchived expires dictionary");
    } else {
        _cachedItemInfos = [NSMutableDictionary dictionary];
        _urlRedirects = [NSMutableDictionary dictionary];
        AFLog(@ "Created new expires dictionary");
    }

    // Deserialize package infos
    NSDictionary *archivedPackageInfos = [NSKeyedUnarchiver unarchiveObjectWithFile: self.infoDictionaryPath];
    if (archivedPackageInfos) {
        _packageInfos = [NSMutableDictionary dictionaryWithDictionary: archivedPackageInfos];
        AFLog(@ "Successfully unarchived package infos dictionary");
    }
    else {
        _packageInfos = [[NSMutableDictionary alloc] init];
        AFLog(@ "Created new package infos dictionary");
    }
    
    // Deserialize metaData

    NSDictionary* metaData = [NSKeyedUnarchiver unarchiveObjectWithFile: self.metaDataDictionaryPath];
    if ([metaData isKindOfClass:[NSDictionary class]]) {
        [self migrateFromVersion:metaData[kAFCacheVersionKey]];
    }
    else
    {
        [self migrateFromVersion:nil];
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
    @synchronized (self.archiveTimer) {
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
}

- (void)archiveNow {
    @synchronized (self.archiveTimer) {
        [self.archiveTimer invalidate];
        [self startArchiveThread:nil];
        [self archive];
    }
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

- (NSString *)filePathForFilename:(NSString *)filename pathExtension:(NSString *)pathExtension
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
    if (!item) {
        return nil;
    }
    
    NSString *fullPath;
    if (!self.cacheWithHashname) {
        return [self filePathForURL:item.url];
    } else {
#if USE_ASSERTS
        NSAssert([item.info.filename length] > 0, @"Filename length MUST NOT be zero! This is a software bug");
#endif
        return [self filePathForFilename:item.info.filename pathExtension:[item.url pathExtension]];
    }
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
    
    NSString *filePath = nil;
    if (!self.cacheWithHashname)
    {
        filePath = [self filePathForURL:info.request.URL];
    }
    else
    {
        if (fallbackURL) {
            filePath = [self filePathForFilename:info.filename pathExtension:[fallbackURL pathExtension]];
        }
        else {
            filePath = [self filePathForFilename:info.filename pathExtension:[info.request.URL pathExtension]];
        }
    }

    BOOL fileNonExistentOrDeleted = [self deleteFileAtPath:filePath];
    
    if (!fileOnly && (fileNonExistentOrDeleted)) {
        if (fallbackURL) {
            [self.cachedItemInfos removeObjectForKey:[fallbackURL absoluteString]];
        }
        else {
            NSURL* requestURL = [info.request URL];
            if (requestURL) {
                 [self.cachedItemInfos removeObjectForKey:[requestURL absoluteString]];
            }
        }
    }
}

-(void)removeCacheEntryAndFileForFileURL:(NSURL*)fileURL
{
    NSSet* results = [self.cachedItemInfos keysOfEntriesPassingTest:^BOOL(id key, id evaluatedObject, BOOL *stop) {
        if ([evaluatedObject isKindOfClass:[AFCacheableItemInfo class]]) {
            return [((AFCacheableItemInfo*)evaluatedObject).filename isEqualToString:[[fileURL lastPathComponent] stringByDeletingPathExtension]];
        }
        return NO;
    }];
    
    if ([results count] > 0) {
        //delete file and entry for files with corresponding infos (should only be one)
        for (NSString* key in results) {
            AFCacheableItemInfo* info = self.cachedItemInfos[key];
            [self removeCacheEntry:info fileOnly:NO fallbackURL:[NSURL URLWithString:key]];
        }
    }
    else
    {
        NSError* error = nil;
        if(![[NSFileManager defaultManager] removeItemAtURL:fileURL error: &error])
        {
            NSLog(@"WARNING: failed to delete orphaned cache file at %@ with error : %@", fileURL, error);
        }
    }
}

-(BOOL)deleteFileAtPath:(NSString*)filePath
{
    BOOL successfullyDeletedFile = NO;
    BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
    NSError* error = nil;
    if (fileExists) {
        successfullyDeletedFile = [[NSFileManager defaultManager] removeItemAtPath: filePath error: &error];
        if (!successfullyDeletedFile)
        {
            AFLog(@ "Failed to delete file for outdated cache item info %@", info);
            NSLog(@"ERROR: failed to delete file %@ because of error: %@", filePath, error);
        }
        else
        {
            AFLog(@ "Successfully removed item at %@", filePath);
        }
    }
    return (!fileExists) || successfullyDeletedFile;
}

#pragma mark internal core methods

- (void)updateModificationDataAndTriggerArchiving: (AFCacheableItem *) cacheableItem {
	NSError *error = nil;
	
	NSString *filePath = [self fullPathForCacheableItem:cacheableItem];
	
	/* reset the file's modification date to indicate that the URL has been checked */
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys: [NSDate date], NSFileModificationDate, nil];
	
	if (![[NSFileManager defaultManager] setAttributes:dict ofItemAtPath:filePath error:&error]) {
		NSLog(@ "Failed to reset modification date for cache item %@", filePath);
	}
	[self archive];
}

- (NSOutputStream*)createOutputStreamForItem:(AFCacheableItem*)cacheableItem
{
    NSString *filePath = [self fullPathForCacheableItem: cacheableItem];
    
	// remove file if exists
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
		[self removeCacheEntry:cacheableItem.info fileOnly:YES];
		AFLog(@"removing %@", filePath);
	}
	
	// create directory if not exists
	NSString *pathToDirectory = [filePath stringByDeletingLastPathComponent];
    BOOL isDirectory = YES;
	if (![[NSFileManager defaultManager] fileExistsAtPath:pathToDirectory isDirectory:&isDirectory] || !isDirectory) {
        NSError* error = nil;
        if (!isDirectory) {
            if (![[NSFileManager defaultManager] removeItemAtPath:pathToDirectory error:&error]) {
                NSLog(@"AFCache: Could not remove directory \"%@\" (Error: %@)", pathToDirectory, [error localizedDescription]);
            }
        }
        if ( [[NSFileManager defaultManager] createDirectoryAtPath:pathToDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
            AFLog(@"creating directory %@", pathToDirectory);
            [AFCache addSkipBackupAttributeToItemAtURL:[NSURL fileURLWithPath:pathToDirectory]];
        } else {
            AFLog(@"Failed to create directory at path %@", pathToDirectory);
        }
	}
	
	// write file
	if (self.maxItemFileSize == kAFCacheInfiniteFileSize || cacheableItem.info.contentLength < self.maxItemFileSize) {
		/* file doesn't exist, so create it */
#if TARGET_OS_IPHONE
        NSDictionary *fileAttributes = @{NSFileProtectionKey:NSFileProtectionNone};
#else
        NSDictionary *fileAttributes = nil;
#endif
        if (![[NSFileManager defaultManager] createFileAtPath:filePath
                                                     contents:nil
                                                   attributes:fileAttributes])
        {
            AFLog(@"Error: could not create file \"%@\"", filePath);
        }
        
        NSURL *fileURL = [NSURL fileURLWithPath:filePath];
        
        [AFCache addSkipBackupAttributeToItemAtURL:fileURL];
        
        NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:fileURL append:NO];
        [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [outputStream open];
        return outputStream;
	}
	else {
		NSLog(@ "AFCache: item %@ \nsize exceeds maxItemFileSize (%f). Won't write file to disk",cacheableItem.url, self.maxItemFileSize);
		[self.cachedItemInfos removeObjectForKey: [cacheableItem.url absoluteString]];
        return nil;
	}
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
        if ([self isQueuedOrDownloadingURL:item.url])
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
    
    AFCacheableItemInfo *info = [self.cachedItemInfos objectForKey: [URL absoluteString]];
    if (!info) {
        NSString *redirectURLString = [self.urlRedirects valueForKey:[URL absoluteString]];
        info = [self.cachedItemInfos objectForKey: redirectURLString];
    }
    if (!info) {
        return nil;
    }
    
    AFLog(@"Cache hit for URL: %@", [URL absoluteString]);

    // check if there is an item in pendingConnections
    AFCacheableItem *cacheableItem;
    AFDownloadOperation *downloadOperation = [self nonCancelledDownloadOperationForURL:URL];
    if ([downloadOperation isExecuting]) {
        // TODO: This concept of AFCache was broken: Returning a running download request does not conform to this method's name
        cacheableItem = downloadOperation.cacheableItem;
    } else {
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

        /*  ======>
         *
         *  This is the place where we check if the URL is already in the queue
         *
         *  TODO: Remove comment as soon as all that internal method got cleaned up
         *
         *  <======
         */


        BOOL fileExistsOrPending = [self _fileExistsOrPendingForCacheableItem:cacheableItem];
        if (!fileExistsOrPending) {
            // Something went wrong
            AFLog(@"Cache info store out of sync for url %@, removing cached file %@.", [URL absoluteString], [self fullPathForCacheableItem:cacheableItem]);
            // TODO: The concept is broken here. Why are we going to delete a file that obviously DOES NOT EXIST? maybe it makes sense when the url is pending?
            [self removeCacheEntry:cacheableItem.info fileOnly:YES];
            cacheableItem = nil;
        }
        else
        {
            //make sure that we continue downloading by setting the length (currently done by reading out file lenth in the info.actualLength accessor)
            cacheableItem.info.cachePath = [self fullPathForCacheableItem:cacheableItem];
        }
    }

    // Update item's status
    if ([self offlineMode]) {
        cacheableItem.cacheStatus = kCacheStatusFresh;
    }
    else if (cacheableItem.isRevalidating) {
        cacheableItem.cacheStatus = kCacheStatusRevalidationPending;
    } else if (nil != cacheableItem.data || !cacheableItem.canMapData) {
        cacheableItem.cacheStatus = [cacheableItem isFresh] ? kCacheStatusFresh : kCacheStatusStale;
    }

    return cacheableItem;
}

#pragma mark - Cancel requests on cache

- (void)cancelAllRequestsForURL:(NSURL *)url {
    if (!url) {
        return;
    }
    for (AFDownloadOperation *downloadOperation in [self.downloadOperationQueue operations]) {
        if ([[downloadOperation.cacheableItem.url absoluteString] isEqualToString:[url absoluteString]]) {
            [downloadOperation cancel];
        }
    }
}

- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)itemDelegate
{
    if (!url || !itemDelegate) {
        return;
    }
    for (AFDownloadOperation *downloadOperation in [self.downloadOperationQueue operations]) {
        if ((downloadOperation.cacheableItem.delegate == itemDelegate) && ([[downloadOperation.cacheableItem.url absoluteString] isEqualToString:[url absoluteString]])) {
            [downloadOperation cancel];
        }
    }
}

- (void)cancelAsynchronousOperationsForDelegate:(id)itemDelegate
{
    if (!itemDelegate) {
        return;
    }

    for (AFDownloadOperation *downloadOperation in [self.downloadOperationQueue operations]) {
        if (downloadOperation.cacheableItem.delegate == itemDelegate) {
            [downloadOperation cancel];
        }
    }
}

- (void)cancelAllDownloads
{
    [self.downloadOperationQueue cancelAllOperations];
}

- (BOOL)isQueuedURL:(NSURL*)url
{
    AFDownloadOperation *downloadOperation = [self nonCancelledDownloadOperationForURL:url];
    return downloadOperation && !([downloadOperation isExecuting] || [downloadOperation isFinished]);
}

- (void)prioritizeURL:(NSURL*)url
{
    [[self nonCancelledDownloadOperationForURL:url] setQueuePriority:NSOperationQueuePriorityVeryHigh];
}

/**
 * Add the item to the downloadQueue
 */
- (void)addItemToDownloadQueue:(AFCacheableItem*)item
{
    if ([self offlineMode]) {
        [item sendFailSignalToClientItems];
        return;
    }

    //check if we can download
    if (![item.url isFileURL] && [self offlineMode]) {
        //we can not download this item at the moment
        [item sendFailSignalToClientItems];
        return;
    }
    
    // check if we are downloading already
    if ([self isDownloadingURL: item.url])
    {
        // don't start another connection
        AFLog(@"We are downloading already. Won't start another connection for %@", item.url);
        return;
    }
    
	NSURLRequest *theRequest = item.info.request;
    
    // no original request, check if we want to send an IMS request
    if (!theRequest) {
        theRequest = item.IMSRequest;
    }
    // this is a reqular request, create a new one
    if (!theRequest) {
        NSTimeInterval timeout = item.isPackageArchive ? self.networkTimeoutIntervals.PackageRequest : self.networkTimeoutIntervals.GETRequest;
        theRequest = [NSMutableURLRequest requestWithURL: item.url
                                             cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval: timeout];
	}

    if ([theRequest isKindOfClass:[NSMutableURLRequest class]])
    {
#ifdef RESUMEABLE_DOWNLOAD
        uint64_t dataAlreadyDownloaded = item.info.actualLength;
        NSString* rangeToDownload = [NSString stringWithFormat:@"%lld-",dataAlreadyDownloaded];
        uint64_t expectedFileSize = item.info.contentLength;
        if(expectedFileSize > 0)
            rangeToDownload = [rangeToDownload stringByAppendingFormat:@"%lld",expectedFileSize];
        AFLog(@"range %@",rangeToDownload);
        [(NSMutableURLRequest*)theRequest setValue:rangeToDownload forHTTPHeaderField:@"Range"];
#endif
        [(NSMutableURLRequest*)theRequest setValue:@"" forHTTPHeaderField:AFCacheInternalRequestHeader];
    }
    
    item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
    item.info.responseTimestamp = 0.0;
    item.info.request = theRequest;
    
    ASSERT_NO_CONNECTION_WHEN_IN_OFFLINE_MODE_FOR_URL(theRequest.URL);

    AFDownloadOperation *downloadOperation = [[AFDownloadOperation alloc] initWithCacheableItem:item];
    [self.downloadOperationQueue addOperation:downloadOperation];
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

#pragma mark - offline mode & pause methods

- (BOOL)suspended {
    return [self.downloadOperationQueue isSuspended];
}

- (void)setSuspended:(BOOL)pause {
    [self.downloadOperationQueue setSuspended:pause];
    [self.packageArchiveQueue setSuspended:pause];

    // TODO: Do we really need to cancel already running downloads? If not, just remove the following lines
	if (pause) {
        // TODO: Cancel current downloads and add running download operations to a list...
    }
	else {
        // TODO: ...whose items are now added back to the queue with highest priority to start downloading them again
	}
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
    if (_connectedToNetwork != connected) {
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
    // url should not be nil nor having a zero length, also it must have a scheme
    return [[url absoluteString] length] > 0 && [[url scheme] length] > 0;
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
#pragma mark helper

-(NSString *)infoDictionaryPath
{
    return [self.dataPath stringByAppendingPathComponent: kAFCachePackageInfoDictionaryFilename];
}

-(NSString *)metaDataDictionaryPath
{
    return [self.dataPath stringByAppendingPathComponent: kAFCacheMetadataFilename];
}

-(NSString *)expireInfoDictionaryPath
{
    return [self.dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
}

#pragma mark migration
-(NSString *)version
{
    if (!_version) {
        _version = [VersionIntrospection sharedIntrospection].versionsForDependency[@"AFCache"];
        if (!_version) {
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSLog(@"ERROR: could not get current version of AFCache");
            });
        }
    }
    return _version;
}

-(BOOL)migrateFromVersion:(NSString*)version
{
    NSString* currentVersion = self.version;
    if (!currentVersion) {
        return NO;
    }
    if (!version || [version length] == 0) {
        if ([currentVersion hasPrefix:@"0.11."]) {
            return [self migrateFromUnversionedToZeroDotEleven];
        }
        else
        {
            NSLog(@"ERROR: unsupportedMigration from %@ to %@", version ?: @"unknown", currentVersion);
        }
    }
    else
    {
        if ([version isEqualToString:currentVersion]) {
            //no migration necessary
            return YES;
        }
        if ([version hasPrefix:@"0.11."] && [currentVersion hasPrefix:@"0.11."]) {
            //no migration should be necessary
            return YES;
        }
        NSLog(@"WARNING: we don't have a migration for %@ of AFCache, this might lead to problems", version);
    }
    return NO;
}

-(BOOL)migrateFromUnversionedToZeroDotEleven
{
    // unknown => 0.11
    [self performBlockOnAllCacheFiles:^(NSURL *url) {
        [AFCache addSkipBackupAttributeToItemAtURL:url];
    }];
    return YES;
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

@end
