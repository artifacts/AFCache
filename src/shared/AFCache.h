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

#ifdef USE_TOUCHXML
#import "TouchXML.h"
#endif
#import "AFCacheableItem.h"
#import "AFRequestConfiguration.h"
#import "AFURLCache.h"

#import <Foundation/NSObjCRuntime.h>

#define kAFCacheExpireInfoDictionaryFilename @"kAFCacheExpireInfoDictionary"
#define kAFCacheRedirectInfoDictionaryFilename @"kAFCacheRedirectInfoDictionary"
#define kAFCachePackageInfoDictionaryFilename @"afcache_packageInfos"
#define kAFCacheMetadataFilename @"afcache_metaData"

#define kAFCacheInfoStoreCachedObjectsKey @"cachedObjects"
#define kAFCacheInfoStoreRedirectsKey @"redirects"
#define kAFCacheInfoStorePackageInfosKey @"packageInfos"
#define kAFCacheVersionKey @"afcacheVersion"

#define LOG_AFCACHE(m) NSLog(m);

#define kAFCacheUserDataFolder @".userdata"

// max cache item size in bytes
#define kAFCacheDefaultMaxFileSize 1000000

// max number of concurrent connections
#define kAFCacheDefaultConcurrentConnections 5

#define kHTTPHeaderIfModifiedSince @"If-Modified-Since"
#define kHTTPHeaderIfNoneMatch @"If-None-Match"

//do housekeeping every nth time archive is called (per session)
#define kHousekeepingInterval 10

#define kDefaultDiskCacheDisplacementTresholdSize 100000000

#define kDefaultNetworkTimeoutIntervalIMSRequest 45
#define kDefaultNetworkTimeoutIntervalGETRequest 100
#define kDefaultNetworkTimeoutIntervalPackageRequest 100

#define kAFCacheNSErrorDomain @"AFCache"
#define USE_ASSERTS true

#define AFCachingURLHeader @"X-AFCache"
#define AFCacheInternalRequestHeader @"X-AFCache-IntReq"

extern const char* kAFCacheContentLengthFileAttribute;
extern const char* kAFCacheDownloadingFileAttribute;
extern const double kAFCacheInfiniteFileSize;

enum {
	kAFCacheInvalidateEntry         = 1 << 9,
    /* Returns cached file (if any) and then performs an IMS request (if file was already cached) or requests file for the first time (if not already cached).
       Option is ignored if kAFCacheNeverRevalidate is set. */
	kAFCacheReturnFileBeforeRevalidation = 1 << 10,
	kAFIgnoreError                  = 1 << 11,
    kAFCacheIsPackageArchive        = 1 << 12,
	kAFCacheRevalidateEntry         = 1 << 13, // revalidate even when cache is running in offline mode
	kAFCacheNeverRevalidate         = 1 << 14,
    kAFCacheJustFetchHTTPHeader     = 1 << 15, // just fetch the http header
};



typedef struct NetworkTimeoutIntervals {
	NSTimeInterval IMSRequest;
	NSTimeInterval GETRequest;
	NSTimeInterval PackageRequest;
} NetworkTimeoutIntervals;

@class AFCache;
@class AFCacheableItem;

@interface AFCache : NSObject

/*
 * YES if offline mode is enabled (no files will be downloaded) or NO if disabled (default).
 */
@property (nonatomic, assign) BOOL offlineMode;

/**
 * Maps from URL-String to AFCacheableItemInfo
 */
@property (nonatomic, strong) NSMutableDictionary *cachedItemInfos;
/**
 * Maps from URL-String to its redirected URL-String
 */
@property (nonatomic, strong) NSMutableDictionary *urlRedirects;
// TODO: "packageInfos" is not a good descriptive name. What means "info"?
@property (nonatomic, strong) NSMutableDictionary *packageInfos;
// holds CacheableItem objects (former NSURLConnection, changed 2013/03/26 by mic)
@property (nonatomic, readonly) int totalRequestsForSession;
@property (nonatomic, strong) NSDictionary *suffixToMimeTypeMap;
@property (nonatomic, assign) double maxItemFileSize;
@property (nonatomic, assign) double diskCacheDisplacementTresholdSize;
@property (nonatomic, assign) NetworkTimeoutIntervals networkTimeoutIntervals;
@property (nonatomic, assign) NSTimeInterval archiveInterval;
/**
 *  Skip check if data on disk is equal to byte size in cache info store. Might be helpful for debugging purposes.
 *
 *  @since 0.9.2
 */
@property (nonatomic, assign) BOOL skipValidContentLengthCheck;

/*
 * change your user agent - do not abuse it
 */
@property (nonatomic, strong) NSString* userAgent;


/*
 * set the path for your cachestore
 */
@property (nonatomic, copy) NSString *dataPath;

/*
 * set the number of maximum concurrent downloadable items
 * Default is 5
 */
// TODO: Rename to maxConcurrentConnections and introduce forward property with old name in DeprecatedAPI category
@property (nonatomic, assign, getter=concurrentConnections, setter=setConcurrentConnections:) int concurrentConnections;

/*
 * the download fails if HTTP error is above 400
 * Default is YES
 */
@property (nonatomic, assign) BOOL failOnStatusCodeAbove400;


/*
 * the items will be cached in the cachestore with a hashed filename instead of the URL path
 * Default is YES
 */
@property (nonatomic, assign) BOOL cacheWithHashname;


/*
 * the items will be cached in the cachestore without any URL parameter
 * Default is NO
 */
@property (nonatomic, assign) BOOL cacheWithoutUrlParameter;

/*
 * the items will be cached in the cachestore without the hostname
 * Default is NO
 */
@property (nonatomic, assign) BOOL cacheWithoutHostname;

/*
 * pause the downloads. cancels any running downloads and puts them back into the queue
 */
@property (nonatomic, assign, getter=suspended, setter=setSuspended:) BOOL suspended;

/*
 * check if we have an internet connection. can be observed
 */
@property (nonatomic, readonly) BOOL isConnectedToNetwork;

/*
 * ignore any invalid SSL certificates
 * be careful with invalid SSL certificates! use only for testing or debugging
 * Default is NO
 */
@property (nonatomic, assign) BOOL disableSSLCertificateValidation;

+ (AFCache*)cacheForContext:(NSString*)context;

- (NSString *)filenameForURL: (NSURL *) url;
- (NSString *)filenameForURLString: (NSString *) URLString;
- (NSString *)filePath: (NSString *) filename;
- (NSString *)filePathForURL: (NSURL *) url;
- (NSString *)fullPathForCacheableItem:(AFCacheableItem*)item;


+ (AFCache *)sharedInstance;


- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                               delegate: (id) aDelegate __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForRequest: (NSURLRequest *) aRequest
                                   delegate: (id) aDelegate __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                               delegate: (id) aDelegate
                                options: (int) options __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
							   delegate: (id) aDelegate
							   selector: (SEL) aSelector
								options: (int) options __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
							   delegate: (id) aDelegate
							   selector: (SEL) aSelector
								options: (int) options
                               userData:(id)userData __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
							   delegate: (id) aDelegate
							   selector: (SEL) aSelector
						didFailSelector: (SEL) aFailSelector
								options: (int) options __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
							   delegate: (id) aDelegate
							   selector: (SEL) aSelector
						didFailSelector: (SEL) aFailSelector
								options: (int) options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword
                                request: (NSURLRequest*)aRequest __attribute__((deprecated("use cacheItemForURL instead")));

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
                                request: (NSURLRequest*)aRequest __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURLSynchronous: (NSURL *) url;
- (AFCacheableItem *)cachedObjectForURLSynchronous:(NSURL *)url options: (int)options;


- (BOOL)isQueuedOrDownloadingURL:(NSURL *)url;
- (BOOL)isDownloadingURL:(NSURL *)url;

- (void)invalidateAll;
- (void)archive;
/**
 * Starts the archiving Thread without a delay.
 */
- (void)archiveNow;
/**
 * NOTE: "offline mode" means: Dear AFCache, please serve everything from cache without making any connections.
 * It does NOT mean that there's no internet connectivity. You may check this by calling "isConnectedToNetwork"]
 */
- (BOOL)offlineMode;
- (void)setOfflineMode:(BOOL)value;
- (int)totalRequestsForSession;
- (void)doHousekeeping;
- (void)doHousekeepingWithRequiredCacheItemURLs:(NSSet*)requiredURLs;

- (BOOL)hasCachedItemForURL:(NSURL *)url;
- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) url;
- (unsigned long)diskCacheSize;

/*
 * Cancel any asynchronous operations and downloads
 */
- (void)cancelAllRequestsForURL:(NSURL *)url;
- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)itemDelegate;
- (void)cancelAsynchronousOperationsForDelegate:(id)itemDelegate;

/*
 * Prioritize the URL or item in the queue
 */
- (void)prioritizeURL:(NSURL*)url;

/*
 * Flush and start loading all items in the  queue
 */
- (void)flushDownloadQueue;

#pragma mark - Public API for getting cache items (do not use any other, replace your existing deprecated calls with new ones)

/*
 * Get a cached item from cache.
 *
 * @param url the requested url
 * @param urlCredential the credential for requested url
 * @param completionBlock
 * @param failBlock
 */
- (AFCacheableItem *)cacheItemForURL:(NSURL *)url
                       urlCredential:(NSURLCredential*)urlCredential
                      completionBlock:(AFCacheableItemBlock)completionBlock
                            failBlock:(AFCacheableItemBlock)failBlock;

/*
 * Get a cached item from cache.
 *
 * @param url the requested url
 * @param urlCredential the credential for requested url
 * @param completionBlock
 * @param failBlock
 * @param progressBlock
 */
- (AFCacheableItem *)cacheItemForURL:(NSURL *)url
                       urlCredential:(NSURLCredential*)urlCredential
                      completionBlock:(AFCacheableItemBlock)completionBlock
                            failBlock:(AFCacheableItemBlock)failBlock
                        progressBlock:(AFCacheableItemBlock)progressBlock;
/*
 * Get a cached item from cache. Lets NSURLSession handle download if session is not nil
 *
 * @param url the requested url
 * @param urlCredential the credential for requested url
 * @param completionBlock
 * @param failBlock
 * @param progressBlock
 * @param session (optional)
 * @param itemID (optional) for session
 */
- (AFCacheableItem*)cacheItemForURL:(NSURL *)url
                      urlCredential:(NSURLCredential *)urlCredential
                    completionBlock:(AFCacheableItemBlock)completionBlock
                          failBlock:(AFCacheableItemBlock)failBlock
                      progressBlock:(AFCacheableItemBlock)progressBlock
                            session:(NSURLSession*)session
                             itemID:(NSString*)itemID;

/*
 * Get a cached item from cache.
 *
 * @param url the requested url
 * @param urlCredential the credential for requested url
 * @param completionBlock
 * @param failBlock
 * @param progressBlock
 * @param requestConfiguration
 */
- (AFCacheableItem *)cacheItemForURL:(NSURL *)url
                       urlCredential:(NSURLCredential*)urlCredential
                     completionBlock:(AFCacheableItemBlock)completionBlock
                           failBlock:(AFCacheableItemBlock)failBlock
                       progressBlock:(AFCacheableItemBlock)progressBlock
                requestConfiguration:(AFRequestConfiguration*)requestConfiguration;

@end

#pragma mark - LoggingSupport

@interface AFCache( LoggingSupport )

/*
 * currently ignored if not built against EngineRoom - SUBJECT TO CHANGE WITHOUT NOTICE
 */

+ (void) setLoggingEnabled: (BOOL) enabled;
+ (void) setLogFormat: (NSString *) logFormat;

@end



@interface AFCache( BLOCKS )

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
								options: (int) options __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
								options: (int) options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword __attribute__((deprecated("use cacheItemForURL instead")));

#pragma mark With progress block

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
                          progressBlock: (AFCacheableItemBlock)aProgressBlock
								options: (int) options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword __attribute__((deprecated("use cacheItemForURL instead")));

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                        completionBlock: (AFCacheableItemBlock)aCompletionBlock
                              failBlock: (AFCacheableItemBlock)aFailBlock
                          progressBlock: (AFCacheableItemBlock)aProgressBlock
								options: (int) options __attribute__((deprecated("use cacheItemForURL instead")));

@end
