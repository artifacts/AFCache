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

#define kAFCacheExpireInfoDictionaryFilename @"kAFCacheExpireInfoDictionary"
#define LOG_AFCACHE(m) NSLog(m);
// max cache item size in bytes
#define kAFCacheDefaultMaxFileSize 100000

//#define AFCACHE_LOGGING_ENABLED
#define kHTTPHeaderIfModifiedSince @"If-Modified-Since"
#define kHTTPHeaderIfNoneMatch @"If-None-Match"

//do housekeeping every nth time archive is called (per session)
#define kHousekeepingInterval 10

#define kDefaultDiskCacheDisplacementTresholdSize 100000000

#define USE_ASSERTS true

extern const char* kAFCacheContentLengthFileAttribute;
extern const char* kAFCacheDownloadingFileAttribute;

enum {
	kAFCacheInvalidateEntry         = 1 << 9,
	//	kAFCacheUseLocalMirror		= 2 << 9, deprecated, don't redefine id 2 for compatibility reasons
	//	kAFCacheLazyLoad			= 3 << 9, deprecated, don't redefine id 3 for compatibility reasons
	kAFIgnoreError                  = 4 << 9,
};


@class AFCache;
@class AFCacheableItem;

@interface AFCache : NSObject {
	BOOL cacheEnabled;
	NSString *dataPath;
	NSMutableDictionary *cacheInfoStore;
	NSMutableDictionary *pendingConnections;
    NSMutableDictionary *clientItems;
	BOOL _offline;
	int requestCounter;
	double maxItemFileSize;
	double diskCacheDisplacementTresholdSize;
	NSDictionary *suffixToMimeTypeMap;
}

@property BOOL cacheEnabled;
@property (nonatomic, copy) NSString *dataPath;
@property (nonatomic, retain) NSMutableDictionary *cacheInfoStore;
@property (nonatomic, retain) NSMutableDictionary *pendingConnections;
@property (nonatomic, retain) NSDictionary *suffixToMimeTypeMap;
@property (nonatomic, readonly) NSDictionary *clientItems;
@property (nonatomic, assign) double maxItemFileSize;
@property (nonatomic, assign) double diskCacheDisplacementTresholdSize;

+ (AFCache *)sharedInstance;

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url options: (int) options;
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url delegate: (id) aDelegate;
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url delegate: (id) aDelegate options: (int) options;
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url delegate: (id) aDelegate selector: (SEL) aSelector options: (int) options;
- (AFCacheableItem *)requestPackageArchive: (NSURL *) url delegate: (id) aDelegate;

- (void)packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem;
- (void)consumePackageArchive:(AFCacheableItem*)cacheableItem;

//- (void)removeObjectForURL: (NSURL *) url fileOnly:(BOOL) fileOnly;
- (void)invalidateAll;
- (void)archive;
- (BOOL)isOffline;
- (void)setOffline:(BOOL)value;
- (BOOL)isConnectedToNetwork;
- (int)totalRequestsForSession;
- (int)requestsPending;
- (void)doHousekeeping;
- (BOOL)hasCachedItemForURL:(NSURL *)url;
- (unsigned long)diskCacheSize;

@end