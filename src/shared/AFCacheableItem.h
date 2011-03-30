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

@interface AFCacheableItem : NSObject {
	NSURL *url;
	NSData *data;
	AFCache *cache;
	id <AFCacheableItemDelegate> delegate;
	BOOL persistable;
	BOOL ignoreErrors;
	SEL connectionDidFinishSelector;
	SEL connectionDidFailSelector;
	NSError *error;
	id userData;
	
	// validUntil holds the calculated expire date of the cached object.
	// It is either equal to Expires (if Expires header is set), or the date
	// based on the request time + max-age (if max-age header is set).
	// If neither Expires nor max-age is given or if the resource must not
	// be cached valitUntil is nil.	
	NSDate *validUntil;
	int cacheStatus;
	AFCacheableItemInfo *info;
	int tag; // for debugging and testing purposes
	BOOL isPackageArchive;
	uint64_t currentContentLength;
    NSFileHandle*   fileHandle;
	
	/*
	 Some data for the HTTP Basic Authentification
	 */
	NSString *username;
	NSString *password;
    
    BOOL    isRevalidating;
}

@property (nonatomic, retain) NSURL *url;

@property (nonatomic, retain) NSData *data;
@property (nonatomic, retain) AFCache *cache;
@property (nonatomic, assign) id <AFCacheableItemDelegate> delegate;
@property (nonatomic, retain) NSError *error;
@property (nonatomic, retain) NSDate *validUntil;
@property (nonatomic, assign) BOOL persistable;
@property (nonatomic, assign) BOOL ignoreErrors;
@property (nonatomic, assign) SEL connectionDidFinishSelector;
@property (nonatomic, assign) SEL connectionDidFailSelector;
@property (nonatomic, assign) int cacheStatus;
@property (nonatomic, retain) AFCacheableItemInfo *info;
@property (nonatomic, assign) id userData;
@property (nonatomic, assign) BOOL isPackageArchive;
@property (nonatomic, assign) uint64_t currentContentLength;
@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *password;

@property (nonatomic, retain) NSFileHandle* fileHandle;
@property (readonly) NSString* filePath;

@property (nonatomic, assign) BOOL isRevalidating;

- (void)connection: (NSURLConnection *) connection didReceiveData: (NSData *) data;
- (void)connectionDidFinishLoading: (NSURLConnection *) connection;
- (void)connection: (NSURLConnection *) connection didReceiveResponse: (NSURLResponse *) response;
- (void)connection: (NSURLConnection *) connection didFailWithError: (NSError *) error;
- (void)handleResponse:(NSURLResponse *)response;
- (BOOL)isFresh;
- (BOOL)isCachedOnDisk;
- (NSString*)guessContentType;
- (void)validateCacheStatus;
- (uint64_t)currentContentLength;
- (BOOL)isComplete;

- (NSString *)filename;
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
- (void) packageArchiveDidReceiveData: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFinishExtracting: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFailExtracting: (AFCacheableItem *) cacheableItem;
- (void) packageArchiveDidFailLoading: (AFCacheableItem *) cacheableItem;

- (void) cacheableItemDidReceiveData: (AFCacheableItem *) cacheableItem;

@end
