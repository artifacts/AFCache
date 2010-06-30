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

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <uuid/uuid.h>
#import <SystemConfiguration/SCNetworkReachability.h>

@implementation AFCache

static AFCache *sharedAFCacheInstance = nil;
static NSString *STORE_ARCHIVE_FILENAME = @ "urlcachestore";

@synthesize cacheEnabled, dataPath, cacheInfoStore, pendingConnections, maxItemFileSize;

#pragma mark init methods

- (id)init {
	self = [super init];
	if (self != nil) {
		[self reinitialize];
	}
	return self;
}

- (int)totalRequestsForSession {
	return requestCounter;
}

- (int)requestsPending {
	return [pendingConnections count];
}

- (void)reinitialize {
	cacheEnabled = YES;
	maxItemFileSize = kAFCacheDefaultMaxFileSize;
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
	requestCounter = 0;
	_offline = NO;
}

// remove all expired cache entries
- (void)doHousekeeping {
	NSDate *now = [NSDate date];
	NSArray *keys = nil;
	NSString *key = nil;
	for (AFCacheableItemInfo *info in cacheInfoStore) {
		if (info.expireDate == [now earlierDate:info.expireDate]) {
			keys = [cacheInfoStore allKeysForObject:info];
			if ([keys count] > 0) {
				key = [keys objectAtIndex:0];				
				[self removeObjectForURLString:key fileOnly:NO];
			}
		}
	}
}


#pragma mark public cache querying methods

#pragma mark assynchronous request methods

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url {
	return [self cachedObjectForURL: url options: 0];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate {
	return [self cachedObjectForURL: url delegate: aDelegate options: 0];
}

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
								options: (int) options {
	return [self cachedObjectForURL: url delegate: aDelegate selector: @selector(connectionDidFinish:) options: options];
}

/*
 * Performs an asynchroneous request and calls delegate when finished loading
 *
 */
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
							   delegate: (id) aDelegate 
							   selector: (SEL) aSelector 
								options: (int) options {
	requestCounter++;
	int invalidateCacheEntry = options & kAFCacheInvalidateEntry;
	
	AFCacheableItem *item = nil;
	if (url != nil) {
		NSURL *internalURL = url;
		// try to get object from disk
		if (self.cacheEnabled && invalidateCacheEntry == 0) {
			item = [self cacheableItemFromCacheStore: internalURL];
			item.delegate = aDelegate;
			item.connectionDidFinishSelector = aSelector;
			item.tag = requestCounter;
		}
		
		// object not in cache. Load it from url.
		if (!item) {
			item = [[[AFCacheableItem alloc] init] autorelease];
			item.connectionDidFinishSelector = aSelector;
			item.cache = self; // calling this particular setter does not increase the retain count to avoid a cyclic reference from a cacheable item to the cache.
			item.delegate = aDelegate;
			item.url = internalURL;
			item.tag = requestCounter;
			
			NSURLRequest *theRequest = [NSURLRequest requestWithURL: internalURL
														cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
													timeoutInterval: 45];
			
			item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
			NSURLConnection *connection = [NSURLConnection connectionWithRequest: theRequest delegate: item];
			[pendingConnections setObject: connection forKey: internalURL];
		} else {
			// object found in cache.
			// now check if it is fresh enough to serve it from disk.			
			
			if ([self isOffline] == YES) {
				item.loadedFromOfflineCache = YES;
				item.cacheStatus = kCacheStatusFresh;
				[aDelegate performSelector: aSelector withObject: item];
				return item;				
			}
			
			// Item is fresh, so call didLoad selector and return the cached item.
			if ([item isFresh]) {
				item.cacheStatus = kCacheStatusFresh;
				//item.info.responseTimestamp = [NSDate timeIntervalSinceReferenceDate];
				[item performSelector:@selector(connectionDidFinishLoading:) withObject:item];
#ifdef AFCACHE_LOGGING_ENABLED
				NSLog(@"serving from cache: %@", item.url);
#endif
				return item;
			}
			// Item is not fresh, fire an If-Modified-Since request
			else {
				// save information that object was in cache and has to be revalidated
				item.cacheStatus = kCacheStatusRevalidationPending;
				NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL: internalURL
																		  cachePolicy: NSURLRequestReloadIgnoringLocalCacheData
																	  timeoutInterval: 45];
				NSDate *lastModified = [NSDate dateWithTimeIntervalSinceReferenceDate: [item.info.lastModified timeIntervalSinceReferenceDate]];
				[theRequest addValue:[DateParser formatHTTPDate:lastModified] forHTTPHeaderField:kHTTPHeaderIfModifiedSince];
				//item.info.requestTimestamp = [NSDate timeIntervalSinceReferenceDate];
				NSURLConnection *connection = [NSURLConnection connectionWithRequest: theRequest delegate: item];
				[pendingConnections setObject: connection forKey: internalURL];				
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
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url 
								options: (int) options {
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
	[self doHousekeeping];
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

// CoreFoundation's hash function for strings does not work well for long very similar strings, e.g. URLs
// (Too many collisions)
- (uint32_t)hash:(NSString*)str {
	const char *s = [str cStringUsingEncoding:NSUTF8StringEncoding];
	/* hash function from Robert Sedgwicks 'Algorithms in C' book */
	const uint32_t b    = 378551;
	uint32_t a          = 63689;	
	uint32_t res = 0;	
	while (*s) {
		res = res * a + (*s++);
		a *= b;
	}	
	return res;
}

- (NSString *)filenameForURL: (NSURL *) url {
	return [self filenameForURLString:[url absoluteString]];
}

- (NSString *)filenameForURLString: (NSString *) URLString {
	NSString *hash = [NSString stringWithFormat: @ "afcache%d", [self hash:URLString]];
#ifdef AFCACHE_LOGGING_ENABLED
	NSLog(@"Created hash %@ for URL: %@", hash, url);
#endif
	return hash;
}

- (NSString *)filePath: (NSString *) filename {
	return [dataPath stringByAppendingPathComponent: filename];
}

- (NSString *)filePathForURL: (NSURL *) url {
	return [dataPath stringByAppendingPathComponent: [self filenameForURL: url]];
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

- (void)removeObjectForURLString: (NSString *) URLString fileOnly:(BOOL) fileOnly {
	NSError *error;
	NSString *filePath = [self filePath: [self filenameForURLString: URLString]];
	if ([[NSFileManager defaultManager] removeItemAtPath: filePath error: &error]) {
		if (fileOnly==NO) {
			[cacheInfoStore removeObjectForKey:URLString];
		}
	} else {
		NSLog(@ "Failed to delete outdated cache item %@", filePath);
	}
}

- (void)removeObjectForURL: (NSURL *) url fileOnly:(BOOL) fileOnly {
	[self removeObjectForURLString: [url absoluteString] fileOnly: fileOnly];
}

#pragma mark internal core methods

- (void)setObject: (AFCacheableItem *) cacheableItem forURL: (NSURL *) url {
	NSString *filePath = [self filePathForURL: url];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath] == YES) {
		[self removeObjectForURL:url fileOnly:YES];		
	} 
	
	if (cacheableItem.data.length < maxItemFileSize) {
		/* file doesn't exist, so create it */
		[[NSFileManager defaultManager] createFileAtPath: filePath
												contents: cacheableItem.data
											  attributes: nil];
#ifdef AFCACHE_LOGGING_ENABLED
		NSLog(@"created file at path %@", filePath);
#endif			
	}
	else {
		NSLog(@ "AFCache: item size exceeds maxItemFileSize (%f). Won't write file to disk", maxItemFileSize);		
		[cacheInfoStore removeObjectForKey: [url absoluteString]];
		return;
	}
	
	
	/* reset the file's modification date to indicate that the URL has been checked */
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys: [NSDate date], NSFileModificationDate, nil];
	NSError *error;
	if (![[NSFileManager defaultManager] setAttributes: dict ofItemAtPath: filePath error: &error]) {
		NSLog(@ "Failed to reset modification date for cache item %@", filePath);
	}
	[dict release];	
	[self archive];
}

- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) URL {
	NSString *filePath = [self filePathForURL: URL];
#ifdef AFCACHE_LOGGING_ENABLED
	NSLog(@"checking for file at path %@", filePath);
#endif	
	if ([[NSFileManager defaultManager] fileExistsAtPath: filePath]) {
		NSMutableData *data = [[NSMutableData alloc] initWithContentsOfFile: filePath];
		AFCacheableItem *cacheableItem = [[AFCacheableItem alloc] init];
		cacheableItem.cache = self;
		cacheableItem.url = URL;
		cacheableItem.data = data;
		cacheableItem.info = [cacheInfoStore objectForKey: [URL absoluteString]];
		NSAssert(cacheableItem.info!=nil, @"AFCache internal inconsistency (cacheableItemFromCacheStore): Info must not be nil. This is a software bug.");
		
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

#pragma mark serialization methods

- (BOOL)fillCacheWithArchiveFromURL:(NSURL *)url
{
    NSURLResponse *response = nil;
    NSError *err = nil;
    
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL: url];
    
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                         returningResponse:&response
                                                     error:&err];
    
    if (nil != err)
    {
        NSLog(@"Error: %@", err);
        return NO;
    }
    
    if ([response respondsToSelector: @selector(statusCode)]) {
        int statusCode = [( (NSHTTPURLResponse *)response )statusCode];
        if (statusCode != 200 && statusCode != 304) {
            [request release];
            return NO;
        }
    }
    
    NSPropertyListFormat format = 0;
    NSString* error = nil;
    NSDictionary* dict = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:0 format:&format errorDescription:&error];
    
    for (NSString* key in dict)
    {
        NSURL* url = [NSURL URLWithString:key];
        if (nil != [self cachedObjectForURL:url])
        {
            continue;
        }
        AFCacheableItem* item = [[[AFCacheableItem alloc] init] autorelease];
        NSDictionary* itemDict = [dict objectForKey:key];
        
        item.url = url;
        item.mimeType = [itemDict objectForKey:@"mimeType"];
        item.data = [itemDict objectForKey:@"data"];
        
        [self setObject:item forURL:item.url];
    }
	
    return YES;
}

- (BOOL)hasCachedItemForURL:(NSURL *)url
{
    return nil != [self cacheableItemFromCacheStore:url];
}

#pragma mark offline methods

- (void)setOffline:(BOOL)value {
	_offline = value;
}

- (BOOL)isOffline {
	return ![self isConnectedToNetwork] || _offline==YES;
}

/*
 * Returns whether we currently have a working connection
 *
 */
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