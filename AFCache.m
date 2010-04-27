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

#import "AFCache+PrivateExtensions.h"
#import <Foundation/NSPropertyList.h>
#import "DateParser.h"

// We need always cached information if we are running in offline mode. Therefore we will
// force caching even if it provides no performance improvements and is disabled usually.
#undef ENABLE_ALWAYS_DO_CACHING_

#ifdef ENABLE_ALWAYS_DO_CACHING_
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <uuid/uuid.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#endif

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;
static NSString *STORE_ARCHIVE_FILENAME = @ "urlcachestore";

@synthesize cacheEnabled, dataPath, cacheInfoStore, pendingConnections;
@synthesize __version;


#pragma mark init methods

- (id)init {
	self = [super init];
	if (self != nil) {
		[self reinitialize];
	}
	return self;
}

- (void)reinitialize {
	cacheEnabled = YES;
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	self.dataPath = [[paths objectAtIndex: 0] stringByAppendingPathComponent: STORE_ARCHIVE_FILENAME];
	NSString *filename = [dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];

	NSDictionary *archivedExpireDates = [NSKeyedUnarchiver unarchiveObjectWithFile: filename];
	if (!archivedExpireDates) {
		NSLog(@ "Created new expires dictionary");
		self.cacheInfoStore = [[NSMutableDictionary alloc] init];
	}
	else {
		self.cacheInfoStore = [NSMutableDictionary dictionaryWithDictionary: archivedExpireDates];
		NSLog(@ "Successfully unarchived expires dictionary");
	}

	self.pendingConnections = [[NSMutableDictionary alloc] init];

	NSError *error;
	/* check for existence of cache directory */
	if ([[NSFileManager defaultManager] fileExistsAtPath: dataPath]) {
		NSLog(@ "Successfully unarchived cache store");
	}
	else {
		if (![[NSFileManager defaultManager] createDirectoryAtPath: dataPath
		      withIntermediateDirectories: YES
		      attributes: nil
		      error: &error]) {
			NSLog(@ "Failed to create cache directory at path %@: %@", dataPath, [error description]);
		}
	}

	//        if(![self isConnectedToNetwork] && alreadyComplainedAboutConnectionError == NO) {
	//            UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"CacheNoConnectionError",@"")
	//                                                                message:NSLocalizedString(@"CacheNoConnectionMessage",@"")
	//                                                               delegate:self
	//                                                      cancelButtonTitle:NSLocalizedString(@"genericOk",@"")
	//                                                      otherButtonTitles:nil];
	//            [alertView show];
	//            [alertView release];
	//            alreadyComplainedAboutConnectionError = complainAboutConnectionErrorsOnlyOnce;
	//        }
}

#pragma mark public cache querying methods

#pragma mark assynchronous request methods

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url {
	return [self cachedObjectForURL: url options: 0];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url delegate: (id) aDelegate {
	return [self cachedObjectForURL: url delegate: aDelegate options: 0];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url delegate: (id) aDelegate options: (int) options {
	return [self cachedObjectForURL: url delegate: aDelegate selector: @selector(connectionDidFinish:) options: options];
}

// performs an asynchroneous request and calls delegate when finished loading
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url delegate: (id) aDelegate selector: (SEL) aSelector options: (int) options {
	int invalidateCacheEntry = options & kAFCacheInvalidateEntry;

	AFCacheableItem *item = nil;
	if (url != nil) {
		NSURL *internalURL = url;
		// try to get object from disk
		if (self.cacheEnabled && invalidateCacheEntry == 0) {
			item = [self cacheableItemFromCacheStore: internalURL];
			item.delegate = aDelegate;
			item.connectionDidFinishSelector = aSelector;
		}
		// object not in cache. Load it from url.
		if (!item) {
			item = [[[AFCacheableItem alloc] init] autorelease];
			item.connectionDidFinishSelector = aSelector;
			item.cache = self; // calling this particular setter does not increase the retain count to avoid a cyclic reference from a cacheable item to the cache.
			item.delegate = aDelegate;
			item.url = internalURL;
			item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];

			NSURLRequest *theRequest = [NSURLRequest requestWithURL: internalURL
			                            cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
			                            timeoutInterval: 45];
			
			NSURLConnection *connection = [NSURLConnection connectionWithRequest: theRequest delegate: item];
			[pendingConnections setObject: connection forKey: internalURL];
		} else {
			// object found in cache.
			// now check if it is fresh enough to serve it from disk.			
			
			// Item is fresh, so call didLoad selector and return the cached item.
			if ([item isFresh]) {
				item.cacheStatus = kCacheStatusFresh;
				[aDelegate performSelector: aSelector withObject: item];
				return item;
			}
			// Item is not fresh, fire an If-Modified-Since request			
			else {
				// save information that object was in cache and has to be revalidated
				item.cacheStatus = kCacheStatusRevalidationPending;
				NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL: internalURL
																		  cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
																	  timeoutInterval: 45];
				NSDate *lastModified = item.info.lastModified;
				[theRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
				NSURLConnection *connection = [NSURLConnection connectionWithRequest: theRequest delegate: item];
				[pendingConnections setObject: connection forKey: internalURL];				
			}
			
		}
		return item;
	}
	return nil;
}

#pragma mark synchronous request methods

// performs a synchroneous request
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url options: (int) options {
	bool invalidateCacheEntry = options & kAFCacheInvalidateEntry;
	//	bool doUseLocalMirror = (options & kAFCacheUseLocalMirror);
	AFCacheableItem *obj = nil;
	if (url != nil) {
		// try to get object from disk if cache is enabled
		if (self.cacheEnabled && !invalidateCacheEntry) {
			obj = [self cacheableItemFromCacheStore: url]; //[self _lookupCachedObjectForURL:url useLocalMirror:doUseLocalMirror];
		}
		// Object not in cache. Load it from url.
		if (!obj) {
			NSURLResponse *response = nil;
			NSError *err = nil;
			NSURLRequest *request = [[NSURLRequest alloc] initWithURL: url];
			NSData *data = [NSURLConnection sendSynchronousRequest: request returningResponse: &response error: &err];
			if ([response respondsToSelector: @selector(statusCode)]) {
				int statusCode = [( (NSHTTPURLResponse *)response )statusCode];
				if (statusCode != 200 && statusCode != 304) {
					[request release];
					return nil;
				}
			}

			if (data != nil) {
				obj = [[[AFCacheableItem alloc] init] autorelease];
				obj.url = url;
				NSMutableData *mutableData = [[NSMutableData alloc] initWithData: data];
				obj.data = mutableData;
				[self setObject: obj forURL: url];
				[mutableData release];
			}
			[request release];
		}
	}
	return obj;
}

#pragma mark file handling methods

- (void)archive {
	NSString *filename = [dataPath stringByAppendingPathComponent: kAFCacheExpireInfoDictionaryFilename];
	BOOL result = [NSKeyedArchiver archiveRootObject: cacheInfoStore toFile: filename];
	if (!result) NSLog(@ "Archiving cache failed.");
}

/* removes every file in the cache directory */
- (void)invalidateAll {
	NSError *error;

	/* remove the cache directory and its contents */
	if (![[NSFileManager defaultManager] removeItemAtPath: dataPath error: &error]) {
		NSLog(@ "Failed to remove cache contents at path: %@", dataPath);
		return;
	}

	/* create a new cache directory */
	if (![[NSFileManager defaultManager] createDirectoryAtPath: dataPath
	      withIntermediateDirectories: NO
	      attributes: nil
	      error: &error]) {
		NSLog(@ "Failed to create new cache directory at path: %@", dataPath);
		return;
	}
	self.cacheInfoStore = [NSMutableDictionary dictionary];
}

- (NSString *)filenameForURL: (NSURL *) url {
	return [NSString stringWithFormat: @ "%d", [[url absoluteString] hash]];
}

- (NSString *)filePath: (NSString *) filename {
	return [dataPath stringByAppendingPathComponent: filename];
}

- (NSString *)filePathForURL: (NSURL *) url {
	return [dataPath stringByAppendingPathComponent: [self filenameForURL: url]];
}

/* get modification date of the current cached image */

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

- (int)numberOfObjectsInDiskCache {
	if ([[NSFileManager defaultManager] fileExistsAtPath: dataPath]) {
		NSArray *directoryContents = [[NSFileManager defaultManager] directoryContentsAtPath: dataPath];
		return [directoryContents count];
	}
	return 0;
}

- (void)removeObjectForURL: (NSURL *) url {
	NSError *error;
	NSString *filePath = [self filePath: [self filenameForURL: url]];
	if (![[NSFileManager defaultManager] removeItemAtPath: filePath error: &error]) {
		//[NSException raise:@"Failed to delete outdated cache item" format:@""];
		NSLog(@ "Failed to delete outdated cache item %@", filePath);
	}
}

#pragma mark internal core methods

- (void)setObject: (AFCacheableItem *) cacheableItem forURL: (NSURL *) url {
	// NSLog(@"%@ --> out %@",self, [url absoluteString]);
	NSString *filePath = [self filePathForURL: url];

	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath] == YES) {
		//		/* apply the modified date policy */
		//		NSDate *fileDate = [self getFileModificationDate:filePath];
		//		NSComparisonResult result = [cacheableItem.lastModified compare:fileDate];
		//		if (result == NSOrderedDescending) {
		[self removeObjectForURL: url];
		//		}
	}
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath] == NO) {
		if (cacheableItem.data.length < kAFCacheMaxFileSize) {
			/* file doesn't exist, so create it */
			[[NSFileManager defaultManager] createFileAtPath: filePath
			 contents: cacheableItem.data
			 attributes: nil];
		}
		else {
			NSLog(@ "AFCache: item size exceeds kAFCacheMaxFileSize. Won't write file to disk");
			[cacheInfoStore removeObjectForKey: url];
			return;
		}
	}

	/* reset the file's modification date to indicate that the URL has been checked */
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys: [NSDate date], NSFileModificationDate, nil];
	NSError *error;
	if (![[NSFileManager defaultManager] setAttributes: dict ofItemAtPath: filePath error: &error]) {
		NSLog(@ "Failed to reset modification date for cache item %@", filePath);
	}
	[dict release];
}

- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) URL {
	NSString *filePath = [self filePathForURL: URL];
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
		NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile: filePath];
		AFCacheableItem *cacheableItem = [[AFCacheableItem alloc] init];
		cacheableItem.cache = self;
		cacheableItem.url = URL;
		cacheableItem.data = data;
		cacheableItem.info.lastModified = [self getFileModificationDate: filePath];
		// TODO: find that corresponding part in RFC again ;) seems to be incorrectly implemented
		//cacheableItem.age = [NSDate timeIntervalSinceReferenceDate] - [cacheableItem.lastModified timeIntervalSinceReferenceDate];
		cacheableItem.info = [cacheInfoStore objectForKey: URL];
		[data release];
		return [cacheableItem autorelease];
	}
	return nil;
}

- (void)cancelConnectionsForURL: (NSURL *) url {
	NSURLConnection *connection = [pendingConnections objectForKey: url];
	[connection cancel];
	[pendingConnections removeObjectForKey: url];
}

- (void)removeReferenceToConnection: (NSURLConnection *) connection {
	for (id keyURL in[pendingConnections allKeysForObject : connection]) {
		[pendingConnections removeObjectForKey: keyURL];
	}
}

#ifdef ENABLE_ALWAYS_DO_CACHING_
// Returns whether we currently have a working connection
- (BOOL)isConnectedToNetwork  {
	// Create zero addy
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

#endif

#pragma mark singleton methods

+ (AFCache *)sharedInstance {
	@synchronized(self) {
		if (sharedAFCacheInstance == nil) {
			sharedAFCacheInstance = [[self alloc] init];
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

- (unsigned)retainCount {
	return UINT_MAX;  //denotes an object that cannot be released
}

- (void)release {
}

- (id)autorelease {
	return self;
}

- (void)dealloc {
	[pendingConnections release];
	[cacheInfoStore release];
	[dataPath release];
	[super dealloc];
}

@end