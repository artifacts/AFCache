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

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "AFCacheableItemInfo.h"

#ifdef USE_TOUCHXML
#import "TouchXML.h"
#endif

@class AFCache;
@class AFCacheableItem;
@protocol AFCacheableItemDelegate;

enum kCacheStatus {
	kCacheStatusNew = 0,
	kCacheStatusFresh = 1, // written into cacheableitem when item is fresh, either after fetching it for the first time or by revalidation.
	kCacheStatusModified = 2, // if ims request returns status 200
	kCacheStatusNotModified = 4,
	kCacheStatusRevalidationPending = 5,
	kCacheStatusStale = 6,
	kCacheStatusDownloading = 7, // item is not fully downloaded
};

#if NS_BLOCKS_AVAILABLE
typedef void (^AFCacheableItemBlock)(AFCacheableItem* item);
#endif

@interface AFCacheableItem : NSObject {
    NSURLRequest *request;

	uint64_t currentContentLength;
    
#if NS_BLOCKS_AVAILABLE
    //block to execute when request completes successfully
	AFCacheableItemBlock completionBlock;
    AFCacheableItemBlock failBlock;
    AFCacheableItemBlock progressBlock;
#endif
}

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) AFCache *cache;
@property (nonatomic, weak) id <AFCacheableItemDelegate> delegate;
@property (nonatomic, strong) NSError *error;
/*
    validUntil holds the calculated expire date of the cached object.
	It is either equal to Expires (if Expires header is set), or the date
	based on the request time + max-age (if max-age header is set).
	If neither Expires nor max-age is given or if the resource must not
	be cached valitUntil is nil.
 */
@property (nonatomic, strong) NSDate *validUntil;
@property (nonatomic, assign) BOOL persistable;
@property (nonatomic, assign) BOOL ignoreErrors;
@property (nonatomic, assign) BOOL justFetchHTTPHeader;
@property (nonatomic, assign) SEL connectionDidFinishSelector;
@property (nonatomic, assign) SEL connectionDidFailSelector;
@property (nonatomic, assign) int cacheStatus;
@property (nonatomic, strong) AFCacheableItemInfo *info;
@property (nonatomic, weak) id userData;
@property (nonatomic, assign) BOOL isPackageArchive;
@property (nonatomic, assign) uint64_t currentContentLength;
/*
 Some data for the HTTP Basic Authentification
 */
@property (nonatomic, strong) NSString *username;
@property (nonatomic, strong) NSString *password;

@property (nonatomic, strong) NSFileHandle* fileHandle;
//@property (readonly) NSString* filePath;

@property (nonatomic, assign) BOOL isRevalidating;
@property (nonatomic, readonly) BOOL canMapData;

@property (nonatomic, weak) NSURLConnection *connection;

#if NS_BLOCKS_AVAILABLE
@property (nonatomic, copy) AFCacheableItemBlock completionBlock;
@property (nonatomic, copy) AFCacheableItemBlock failBlock;
@property (nonatomic, copy) AFCacheableItemBlock progressBlock;
#endif

@property (nonatomic, strong) NSURLRequest *IMSRequest;
@property (nonatomic, assign) BOOL servedFromCache;
@property (nonatomic, assign) BOOL URLInternallyRewritten;

// for debugging and testing purposes
@property (nonatomic, assign) int tag;


- (AFCacheableItem*)initWithURL:(NSURL*)URL
                   lastModified:(NSDate*)lastModified
                     expireDate:(NSDate*)expireDate
                    contentType:(NSString*)contentType;

- (AFCacheableItem*)initWithURL:(NSURL*)URL
                   lastModified:(NSDate*)lastModified
                     expireDate:(NSDate*)expireDate;

- (void)connection: (NSURLConnection *) connection didReceiveData: (NSData *) data;
- (void)connectionDidFinishLoading: (NSURLConnection *) connection;
- (void)connection: (NSURLConnection *) connection didReceiveResponse: (NSURLResponse *) response;
- (void)connection: (NSURLConnection *) connection didFailWithError: (NSError *) error;
- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)handleResponse:(NSURLResponse *)response;
- (BOOL)isFresh;
- (BOOL)isCachedOnDisk;
- (NSString*)guessContentType;
- (void)validateCacheStatus;
- (uint64_t)currentContentLength;
- (BOOL)isComplete;
- (BOOL)isDataLoaded;
- (BOOL)isDownloading;

- (NSString *)asString;
- (NSString*)mimeType __attribute__((deprecated)); // mimeType moved to AFCacheableItemInfo. 
// This method is implicitly guessing the mimetype which might be confusing because there's a property mimeType in AFCacheableItemInfo.

#ifdef USE_TOUCHXML
- (CXMLDocument *)asXMLDocument;
#endif

@end

@protocol AFCacheableItemDelegate < NSObject >


@optional
- (void) connectionDidFail: (AFCacheableItem *) cacheableItem;
- (void) connectionDidFinish: (AFCacheableItem *) cacheableItem;
- (void) connectionHasBeenRedirected: (AFCacheableItem *) cacheableItem;

- (void) packageArchiveDidReceiveData: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFinishExtracting: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFailExtracting: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFailLoading: (AFCacheableItem *) cacheableItem;

- (void) cacheableItemDidReceiveData: (AFCacheableItem *) cacheableItem;

@end
