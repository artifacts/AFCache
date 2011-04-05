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
#import "AFURLCache.h"

#import <Foundation/NSObjCRuntime.h>

#define kAFCacheExpireInfoDictionaryFilename @"kAFCacheExpireInfoDictionary"
#define kAFCachePackageInfoDictionaryFilename @"afcache_packageInfos"

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
#define kDefaultNetworkTimeoutIntervalPackageRequest 10

#define kAFCacheNSErrorDomain @"AFCache"

#define USE_ASSERTS true

extern const char* kAFCacheContentLengthFileAttribute;
extern const char* kAFCacheDownloadingFileAttribute;
extern const double kAFCacheInfiniteFileSize;

enum {
	kAFCacheInvalidateEntry         = 1 << 9,
	//	kAFCacheUseLocalMirror		= 2 << 9, deprecated, don't redefine id 2 for compatibility reasons
	//	kAFCacheLazyLoad			= 3 << 9, deprecated, don't redefine id 3 for compatibility reasons
	kAFIgnoreError                  = 1 << 11,
    kAFCacheIsPackageArchive        = 1 << 12,
	kAFCacheRevalidateEntry         = 1 << 13, // revalidate even when cache is switched to offline
	kAFCacheNeverRevalidate         = 1 << 14,    
};

typedef struct NetworkTimeoutIntervals {
	NSTimeInterval IMSRequest;
	NSTimeInterval GETRequest;
	NSTimeInterval PackageRequest;
} NetworkTimeoutIntervals;

@class AFCache;
@class AFCacheableItem;

@interface AFCache : NSObject {
	BOOL cacheEnabled;
	NSString *dataPath;
	NSMutableDictionary *cacheInfoStore;
	NSMutableDictionary *pendingConnections;
    NSMutableDictionary *clientItems;
	NSMutableArray		*downloadQueue;
	BOOL _offline;
	int requestCounter;
	int concurrentConnections;
	double maxItemFileSize;
	double diskCacheDisplacementTresholdSize;
	NSDictionary *suffixToMimeTypeMap;
    NSTimer* archiveTimer;
	
	BOOL downloadPermission_;
    BOOL wantsToArchive_;
	
	NetworkTimeoutIntervals networkTimeoutIntervals;
	NSMutableDictionary *packageInfos;
    
    NSOperationQueue* packageArchiveQueue_;
	BOOL failOnStatusCodeAbove400;
}


@property BOOL cacheEnabled;
@property (nonatomic, copy) NSString *dataPath;
@property (nonatomic, retain) NSMutableDictionary *cacheInfoStore;
@property (nonatomic, retain) NSMutableDictionary *pendingConnections;
@property (nonatomic, retain) NSMutableArray *downloadQueue;
@property (nonatomic, retain) NSDictionary *suffixToMimeTypeMap;
@property (nonatomic, retain) NSDictionary *clientItems;
@property (nonatomic, assign) double maxItemFileSize;
@property (nonatomic, assign) double diskCacheDisplacementTresholdSize;
@property (nonatomic, assign) int concurrentConnections;
@property BOOL downloadPermission;
@property (nonatomic, assign) NetworkTimeoutIntervals networkTimeoutIntervals;
@property (nonatomic, retain) NSMutableDictionary *packageInfos;
@property (nonatomic, assign) BOOL failOnStatusCodeAbove400;
		
+ (AFCache *)sharedInstance;


- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                               delegate: (id) aDelegate;

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url
                               delegate: (id) aDelegate
                                options: (int) options;

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
							   selector: (SEL) aSelector 
						didFailSelector: (SEL) aFailSelector 
								options: (int) options;

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
							   selector: (SEL) aSelector 
						didFailSelector: (SEL) aFailSelector 
								options: (int) options
                               userData: (id)userData
							   username: (NSString *)aUsername
							   password: (NSString *)aPassword;

- (AFCacheableItem *)cachedObjectForURL:(NSURL *)url 
							   delegate:(id) aDelegate 
							   selector:(SEL)aSelector 
						didFailSelector:(SEL)didFailSelector 
								options: (int) options;


- (AFCacheableItem *)cachedObjectForURLSynchroneous: (NSURL *) url;
- (AFCacheableItem *)cachedObjectForURLSynchroneous: (NSURL *) url options: (int)options;

- (void)invalidateAll;
- (void)archive;
- (BOOL)isOffline;
- (void)setOffline:(BOOL)value;
- (BOOL)isConnectedToNetwork;
- (int)totalRequestsForSession;
- (NSUInteger)requestsPending;
- (void)doHousekeeping;
- (BOOL)hasCachedItemForURL:(NSURL *)url;
- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) url;
- (unsigned long)diskCacheSize;
- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)aDelegate;
- (void)cancelAsynchronousOperationsForURL:(NSURL *)url itemDelegate:(id)aDelegate didLoadSelector:(SEL)selector;
- (void)cancelAsynchronousOperationsForDelegate:(id)aDelegate;
- (NSArray*)cacheableItemsForURL:(NSURL*)url;
- (void)flushDownloadQueue;

@end

@interface AFCache( LoggingSupport ) 

/*
 * currently ignored if not built against EngineRoom - SUBJECT TO CHANGE WITHOUT NOTICE
 */

+ (void) setLoggingEnabled: (BOOL) enabled; 
+ (void) setLogFormat: (NSString *) logFormat;

@end
