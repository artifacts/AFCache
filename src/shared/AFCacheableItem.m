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

#import "AFCacheableItem.h"
#import "AFCache+PrivateAPI.h"
#import "AFCache.h"
#import "DateParser.h"
#import "AFRegexString.h"
#import "AFCache_Logging.h"
#include <sys/xattr.h>

@implementation AFCacheableItem

@synthesize url, data, persistable, ignoreErrors;
@synthesize cache, delegate, connectionDidFinishSelector, connectionDidFailSelector, error;
@synthesize info, validUntil, cacheStatus, userData, isPackageArchive, fileHandle, currentContentLength;
@synthesize username, password;
@synthesize isRevalidating;


- (id) init {
	self = [super init];
	if (self != nil) {
		data = nil;
		persistable = true;
		connectionDidFinishSelector = @selector(connectionDidFinish:);
		connectionDidFailSelector = @selector(connectionDidFail:);
		self.cacheStatus = kCacheStatusNew;
		info = [[AFCacheableItemInfo alloc] init];
	}
	return self;
}

- (void)appendData:(NSData*)newData {
    [fileHandle seekToEndOfFile];
    [fileHandle writeData:newData];
}

- (NSData*)data {
    if (nil == data) {
  
		if (NO == [self hasValidContentLength])
		{
			if ([[self.cache pendingConnections] objectForKey:self.url] != nil)
			{
				cacheStatus = kCacheStatusDownloading;
			}
			
			return nil;
		}
		
		NSString* filePath = [self.cache filePath:self.filename];
		if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
		{
			return nil;
		}
		
        data = [[NSData dataWithContentsOfMappedFile:filePath] retain];
        
        if (nil == data)
        {
            NSLog(@"Error: Could not map file %@", filePath);
        }
    }
	
    return data;
}

- (void)connection: (NSURLConnection *) connection didReceiveData: (NSData *) receivedData {
	[self appendData:receivedData];
	currentContentLength += [receivedData length];
	if (self.isPackageArchive) {
        [self.cache signalItemsForURL:self.url usingSelector:@selector(packageArchiveDidReceiveData:)];
	}
	[self.cache signalItemsForURL:self.url usingSelector:@selector(cacheableItemDidReceiveData:)];
}

- (void)handleResponse:(NSURLResponse *)response
{
	self.info.mimeType = [response MIMEType];
	BOOL mustNotCache = NO;
	NSDate *now = [NSDate date];
	NSDate *newLastModifiedDate = nil;
	
#if USE_ASSERTS
	NSAssert(info!=nil, @"AFCache internal inconsistency (connection:didReceiveResponse): Info must not be nil");
#endif
	// Get HTTP-Status code from response
	NSUInteger statusCode = 200;
	if ([response respondsToSelector:@selector(statusCode)]) {
		statusCode = (NSUInteger)[response performSelector:@selector(statusCode)];
	}
	self.info.statusCode = statusCode;
	
	// The resource has not been modified, so we call connectionDidFinishLoading and exit here.
	if (self.cacheStatus==kCacheStatusRevalidationPending) {
		switch (statusCode) {
			case 304:
				self.cacheStatus = kCacheStatusNotModified;
				self.validUntil = info.expireDate;
				return;
			case 200:
				self.cacheStatus = kCacheStatusModified;
				
				break;
		}
	} else {
		self.info.responseTimestamp = [now timeIntervalSinceReferenceDate];
	}
	
    if (200 == statusCode)
    {
        self.fileHandle = [self.cache createFileForItem:self];
    }
	
	// Calulate expiration time for newly fetched object to determine
	// until when we may cache it.
	if ([response isKindOfClass: [NSHTTPURLResponse self]]) {
		
		// get all headers from response
		NSDictionary *headers = [(NSHTTPURLResponse *) response allHeaderFields];
		
#ifdef AFCACHE_LOGGING_ENABLED
		// log headers
		NSLog(@"status code: %d", statusCode);
		for (NSString *key in[headers allKeys]) {
			NSString *logString = [NSString stringWithFormat: @"%@: %@", key, [headers objectForKey: key]];
			NSLog(@"Headers: %@", logString);
		}
#endif
		// get headers that are used for cache control
		NSString *ageHeader                     = [headers objectForKey: @"Age"];
		NSString *dateHeader                    = [headers objectForKey: @"Date"];
		NSString *modifiedHeader                = [headers objectForKey: @"Last-Modified"];
		NSString *expiresHeader                 = [headers objectForKey: @"Expires"];
		NSString *cacheControlHeader                    = [headers objectForKey: @"Cache-Control"];
		NSString *pragmaHeader                  = [headers objectForKey: @"Pragma"];
		NSString *eTagHeader                                    = [headers objectForKey: @"Etag"];
		NSString *contentLengthHeader                   = [headers objectForKey: @"Content-Length"];
		
		self.info.contentLength = [contentLengthHeader integerValue];
		
		
		[self setDownloadStartedFileAttributes];
		
		
		// parse 'Age', 'Date', 'Last-Modified', 'Expires' headers and use
		// a date formatter capable of parsing the date string using
		// three different formats:
		// Excerpt from rfc2616: http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3
		// The first format is preferred as an Internet standard and represents a
		// fixed-length subset of that defined by RFC 1123 [8] (an update to RFC 822 [9]).
		// The second format is in common use, but is based on the obsolete RFC 850 [12] date
		// format and lacks a four-digit year. HTTP/1.1 clients and servers that parse the
		// date value MUST accept all three formats (for compatibility with HTTP/1.0),
		// though they MUST only generate the RFC 1123 format for representing HTTP-date
		// values in header fields. See section 19.3 for further information.
		
		self.info.age = (ageHeader) ? [ageHeader intValue] : 0;
		self.info.serverDate = (dateHeader) ? [DateParser gh_parseHTTP: dateHeader] : now;
		newLastModifiedDate = (modifiedHeader) ? [DateParser gh_parseHTTP: modifiedHeader] : now;
		
		// Store expire date from header or nil
		self.info.expireDate = (expiresHeader) ? [DateParser gh_parseHTTP: expiresHeader] : nil;
		
		// Update lastModifiedDate for cached object
		self.info.lastModified = newLastModifiedDate;
		
		// set validity to current last modified date. Might be overwritten later by
		// expireDate (from server) or new calculated expiration date (if max-age is set)
		// Only if validUntil is set, the resource is written into the cache
		self.validUntil = newLastModifiedDate;
		self.info.eTag = eTagHeader;
		
		// These values are fetched while parsing the headers and used later to
		// compute if the resource may be cached.
		BOOL pragmaNoCacheSet = NO;
		BOOL maxAgeIsZero = NO;
		BOOL maxAgeIsSet = NO;
		self.info.maxAge = nil;
		
		// parse "Pragma" header
		if (pragmaHeader) {
			// check if Pragma: no-cache is set (for compatibilty with HTTP/1.0 clients
			NSRange range = [pragmaHeader rangeOfString: @"no-cache"];
			pragmaNoCacheSet = (range.location != NSNotFound);
		}
		
		// parse cache-control header, if given
		if (cacheControlHeader) {
			
			// check if max-age is set in header
			
			NSRange range = [cacheControlHeader rangeOfString: @"max-age="];
			maxAgeIsSet = (range.location != NSNotFound);
			if (maxAgeIsSet) {
				
				// max-age is set, parse seconds
				// The 'max-age' directive takes priority over 'Expires', so we overwrite validUntil,
				// no matter if it was already set by 'Expires'
				
				unsigned long start = range.location + range.length;
				unsigned long length =  [cacheControlHeader length] - (range.location + range.length);
				NSString *numStr = [cacheControlHeader substringWithRange: NSMakeRange(start, length)];
				self.info.maxAge = [NSNumber numberWithInt: [numStr intValue]];
				// create future expire date for max age by adding the given seconds to now
#if ((TARGET_OS_IPHONE == 0 && 1060 <= MAC_OS_X_VERSION_MAX_ALLOWED) || (TARGET_OS_IPHONE == 1 && 40000 <= __IPHONE_OS_VERSION_MAX_ALLOWED))
                self.validUntil = [now dateByAddingTimeInterval: [info.maxAge doubleValue]];
#else
				self.validUntil = [now addTimeInterval: [info.maxAge doubleValue]];
#endif
			}
			
			// check no-cache in "Cache-Control"
			// see http://www.ietf.org/rfc/rfc2616.txt - 14.9 Cache-Control, Page 107

			range = [cacheControlHeader rangeOfString: @"no-cache"];
			if (range.location != NSNotFound)
			{
				pragmaNoCacheSet = YES;
			}			
		}
		
		// If expires is given, adjust validUntil date
		if (info.expireDate) self.validUntil = info.expireDate;
		
		// if either "Pragma: no-cache" is set in the header, or max-age=0 is set then
		// this resource must not be cached.
		mustNotCache = pragmaNoCacheSet || maxAgeIsSet && maxAgeIsZero;
		if (mustNotCache) self.validUntil = nil;
	}
}
/*
 *
 @discussion This method gives the delegate an opportunity to
 inspect the request that will be used to continue loading the
 request, and modify it if necessary. The URL-change determinations
 mentioned above can occur as a result of transforming a request
 URL to its canonical form, or can happen for protocol-specific
 reasons, such as an HTTP redirect.
 *
 */
- (NSURLRequest *)connection: (NSURLConnection *)inConnection
             willSendRequest: (NSURLRequest *)inRequest
            redirectResponse: (NSURLResponse *)inRedirectResponse;
{
    if (inRedirectResponse)
	{
        NSMutableURLRequest *request = [[inRequest mutableCopy] autorelease];
        [request setURL: [inRequest URL]];
		self.info.responseURL =  [inRequest URL];
        return request;
    }
	
	return inRequest;
}

/*
 * this method is called when the server has determined that it
 * has enough information to create the NSURLResponse
 * it can be called multiple times, for example in the case of a
 * redirect, so each time we reset the data.
 *
 * After the response headers are parsed, we try to load the object
 * from disk. If the cached object is fresh, we call connectionDidFinishLoading:
 * with the cached object and cancel the original request.
 * If the object is stale, we go on with the request.
 */

- (void)connection: (NSURLConnection *) connection didReceiveResponse: (NSURLResponse *) response {
	
#ifdef AFCACHE_MAINTAINER_WARNINGS
#warning TODO what about caching 403 (forbidden) ? RTFM.
#endif
	
	[self handleResponse:response];
	
	// call didFailSelector when statusCode >= 400
	if (cache.failOnStatusCodeAbove400 == YES && self.info.statusCode >= 400) {
		[self connection:connection didFailWithError:[NSError errorWithDomain:kAFCacheNSErrorDomain code:self.info.statusCode userInfo:nil]];
		return;
	}
	
	if (validUntil) {
		AFLog(@"Setting info for Object at %@ to %@", [url absoluteString], [info description]);
#if USE_ASSERTS
		NSAssert(info!=nil, @"AFCache internal inconsistency (connection:didReceiveResponse): Info must not be nil");
#endif
		NSString *key = [cache filenameForURL:url];
		[cache.cacheInfoStore setObject: info forKey: key];
	}
}

/*
 If implemented, will be called before connection:didReceiveAuthenticationChallenge
 to give the delegate a chance to inspect the protection space that will be authenticated against.  Delegates should determine
 if they are prepared to respond to the authentication method of the protection space and if so, return YES, or NO to
 allow default processing to handle the authentication.
 */
- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
	
	
	return (self.username && self.password);
}

/*
 *      The connection is called when we get a basic http authentification
 *  If so, login with the given username and passwort
 *  if login was wrong then cancel the connection
 */

- (void) connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	if([challenge previousFailureCount] == 0 && nil != self.username && nil != self.password) {
		NSString *usr = self.username;
		NSString *pss = self.password;
		NSURLCredential *newCredential;
		newCredential = [NSURLCredential credentialWithUser:usr password:pss persistence:NSURLCredentialPersistenceForSession];
		[[challenge sender] useCredential:newCredential forAuthenticationChallenge:challenge];
	}
	
	// last auth failed, abort!
	else
	{
		[self connection:connection didCancelAuthenticationChallenge:challenge];
		
	}
}

- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	NSError *err = [NSError errorWithDomain: @"HTTP Authentifcation failed" code: 99 userInfo: nil];
	[self connection:connection didFailWithError:err];
}



/*
 *      The connection did finish loading. Everything should be okay at this point.
 *  If so, store object into cache and call delegate.
 *  If the server has not been delivered anything (response body is 0 bytes)
 *  we won't cache the response.
 */
- (void)connectionDidFinishLoading: (NSURLConnection *) connection {
    NSError *err = nil;
	
    // note: No longer an error, because the data is written directly to disk
    //if ([self.data length] == 0) err = [NSError errorWithDomain: @"Request returned no data" code: 99 userInfo: nil];
    if (url == nil) err = [NSError errorWithDomain: @"URL is nil" code: 99 userInfo: nil];
    
    // do we have a correct contentLength?
    NSDictionary* attr = [[NSFileManager defaultManager] attributesOfItemAtPath:[self.cache filePath:self.filename]
                                                                          error:&err];
    if (nil == err)
    {
        uint64_t fileSize = [attr fileSize];
        if (fileSize != self.info.contentLength)
        {
            self.info.contentLength = fileSize;
        }
    }
    [self setDownloadFinishedFileAttributes];
    [fileHandle closeFile];
    [fileHandle release];
    fileHandle = nil;
    
    // Log any error. Maybe someone might read it ;)
    if (err != nil) {
        NSLog(@"Error: %@", [err localizedDescription]);
    } else {
        
        // Only cache response if it has a validUntil date
        // and only if we're not in offline mode.
        
        if (validUntil) {
            AFLog(@"Storing object for URL: %@", [url absoluteString]);
            // Put the object into the cache
            [(AFCache *)self.cache setObject: self forURL: url];
        }
    }
    
    // Remove reference to pending connection to unlink the item from the cache
    [cache removeReferenceToConnection: connection];
	[cache removeFromDownloadQueueAndLoadNext:self];
	
	
	
    NSArray* items = [self.cache cacheableItemsForURL:self.url];
    
    // make sure we survive being released in the following call
    [[self retain] autorelease];
    
    [self.cache removeItemsForURL:self.url];
    
    // Call delegate for this item
    if (self.isPackageArchive) {
        [cache performSelector:@selector(packageArchiveDidFinishLoading:) withObject:self];
    } else {
        [self signalItemsDidFinish:items];
    }
    
}

- (void)signalItems:(NSArray*)items usingSelector:(SEL)selector
{
    for (AFCacheableItem* item in items)
    {
        id itemDelegate = item.delegate;
        if ([itemDelegate respondsToSelector:selector])
        {
            [itemDelegate performSelector:selector withObject:item afterDelay:0.0];
        }
    }
}

- (void)signalItemsDidFinish:(NSArray*)items
{
	for (AFCacheableItem* item in items)
    {
        id itemDelegate = item.delegate;
		SEL selector = item.connectionDidFinishSelector;
        if ([itemDelegate respondsToSelector:selector])
        {
            [itemDelegate performSelector:selector withObject:item afterDelay:0.0];
		}
    }
	
}

- (void)signalItemsDidFail:(NSArray*)items
{
	for (AFCacheableItem* item in items)
    {
        id itemDelegate = item.delegate;
		SEL selector = item.connectionDidFailSelector;
        if ([itemDelegate respondsToSelector:selector])
        {
            [itemDelegate performSelector:selector withObject:item afterDelay:0.0];
        }
    }
	
}

/*
 *      The connection did fail. Remove object info from cache and call delegate.
 */

- (void)connection: (NSURLConnection *) connection didFailWithError: (NSError *) anError
{
    [fileHandle closeFile];
    [fileHandle release];
    fileHandle = nil;
    [cache removeReferenceToConnection: connection];
	[cache removeFromDownloadQueueAndLoadNext:self];
	
	if (nil != self.data && self.isRevalidating)
    {
        // we should revalidate, but did fail. Maybe we have no network?
        // return what we have in this case.
        
        NSArray* items = [self.cache cacheableItemsForURL:self.url];
        [self.cache removeItemsForURL:self.url];
        
        if (self.isPackageArchive) {
            [self signalItems:items usingSelector:@selector(packageArchiveDidFinishLoading:)];
        } else {
            [self signalItemsDidFinish:items];
        }
        
    }
    else
    {
        self.error = anError;
        [cache.cacheInfoStore removeObjectForKey:[url absoluteString]];
        
        NSArray* items = [self.cache cacheableItemsForURL:self.url];
        [self.cache removeItemsForURL:self.url];
        
        if (self.isPackageArchive) {
            [self signalItems:items usingSelector:@selector(packageArchiveDidFailLoading:)];
        } else {
            [self signalItemsDidFail:items];
        }
    }
}

/*
 * calculate freshness of object according to algorithm in rfc2616
 * http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html
 *
 * age_value
 *      is the value of Age: header received by the cache with this response.
 * date_value
 *      is the value of the origin server's Date: header
 * request_time
 *      is the (local) time when the cache made the request that resulted in this cached response
 * response_time
 *      is the (local) time when the cache received the response
 * now
 *      is the current (local) time
 */

- (BOOL)isFresh {
	
#if USE_ASSERTS
	NSAssert(info!=nil, @"AFCache internal inconsistency detected while validating freshness. AFCacheableItem's info object must not be nil. This is a software bug.");
#endif
	
	NSTimeInterval apparent_age = fmax(0, info.responseTimestamp - [info.serverDate timeIntervalSinceReferenceDate]);
	NSTimeInterval corrected_received_age = fmax(apparent_age, info.age);
	NSTimeInterval response_delay = (info.responseTimestamp>0)?info.responseTimestamp - info.requestTimestamp:0;
	
#if USE_ASSERTS
	NSAssert(response_delay >= 0, @"response_delay must never be negative!");
#endif
	
	NSTimeInterval corrected_initial_age = corrected_received_age + response_delay;
	NSTimeInterval resident_time = [NSDate timeIntervalSinceReferenceDate] - info.responseTimestamp;
	NSTimeInterval current_age = corrected_initial_age + resident_time;
	
	NSTimeInterval freshness_lifetime = 0;
	
	if (info.expireDate) {
		freshness_lifetime = [info.expireDate timeIntervalSinceReferenceDate] - [info.serverDate timeIntervalSinceReferenceDate];
	}
	
	// The max-age directive takes priority over Expires! Thanks, Serge ;)
	if (info.maxAge) {
		freshness_lifetime = [info.maxAge doubleValue];
	}
	
	// Note:
	// If none of Expires, Cache-Control: max-age, or Cache-Control: s- maxage (see section 14.9.3) appears in the response,
	// and the response does not include other restrictions on caching, the cache MAY compute a freshness lifetime using a heuristic.
	// The cache MUST attach Warning 113 to any response whose age is more than 24 hours if such warning has not already been added.
	
	BOOL fresh = (freshness_lifetime > current_age);
	AFLog(@"freshness_lifetime: %@", [NSDate dateWithTimeIntervalSinceReferenceDate: freshness_lifetime]);
	AFLog(@"current_age: %@", [NSDate dateWithTimeIntervalSinceReferenceDate: current_age]);
	
	return fresh;
}

- (void)validateCacheStatus {
    if ([self isDownloading]) {
        self.cacheStatus = kCacheStatusDownloading;
    } else if (self.isRevalidating) {
        self.cacheStatus = kCacheStatusRevalidationPending;
    } else if (nil != self.data) {
        self.cacheStatus = [self isFresh] ? kCacheStatusFresh : kCacheStatusStale;
        return;
    }
}

- (void)setDownloadStartedFileAttributes {
    int fd = [self.fileHandle fileDescriptor];
    if (fd > 0) {
		uint64_t contentLength = info.contentLength;
        if (0 != fsetxattr(fd,
                           kAFCacheContentLengthFileAttribute,
                           &contentLength,
                           sizeof(uint64_t),
                           0, 0)) {
            AFLog(@"Could not set contentLength attribute on %@", [self filename]);
        }
		
        unsigned int downloading = 1;
        if (0 != fsetxattr(fd,
                           kAFCacheDownloadingFileAttribute,
                           &downloading,
                           sizeof(downloading),
                           0, 0)) {
            AFLog(@"Could not set downloading attribute on %@", [self filename]);
        }
		
    }
}

- (void)setDownloadFinishedFileAttributes
{
    int fd = [self.fileHandle fileDescriptor];
    if (fd > 0)
    {
		uint64_t contentLength = info.contentLength;
        if (0 != fsetxattr(fd,
                           kAFCacheContentLengthFileAttribute,
                           &contentLength,
                           sizeof(uint64_t),
                           0, 0))
        {
            AFLog(@"Could not set contentLength attribute on %@, errno = %ld", [self filename], (long)errno );
        }
		
        if (0 != fremovexattr(fd, kAFCacheDownloadingFileAttribute, 0))
        {
            AFLog(@"Could not remove downloading attribute on %@, errno = %ld", [self filename], (long)errno );
        }
    }
}

- (BOOL)hasDownloadFileAttribute
{
    unsigned int downloading = 0;
    if (sizeof(downloading) != getxattr([[self.cache filePathForURL:self.url] fileSystemRepresentation],
                                        kAFCacheDownloadingFileAttribute,
                                        &downloading,
                                        sizeof(downloading),
                                        0, 0))
    {
        return NO;
    }
	
	return YES;
}

- (BOOL)hasValidContentLength
{
	NSString* filePath = [self.cache filePath:self.filename];
	if (![[NSFileManager defaultManager] fileExistsAtPath:filePath])
	{
		return NO;
	}
	
	NSError* err = nil;
	NSDictionary* attr = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&err];
	if (nil != err)
	{
		AFLog(@"Error getting file attributes: %@", err);
		return NO;
	}
	
	uint64_t fileSize = [attr fileSize];
	if (self.info.contentLength == 0 || fileSize != self.info.contentLength)
	{
		uint64_t realContentLength = [self getContentLengthFromFile];
		
		if (realContentLength == 0 || realContentLength != fileSize)
		{
			return NO;
		}
	}
	
	return YES;
}

- (BOOL)isDownloading
{
    return ([[self.cache pendingConnections] objectForKey:self.url] != nil
			|| [self.cache isQueuedURL:self.url]);
}


- (uint64_t)getContentLengthFromFile
{
    if ([self isDownloading])
    {
        return 0LL;
    }
	
    uint64_t realContentLength = 0LL;
    ssize_t const size = getxattr([[self.cache filePathForURL:self.url] fileSystemRepresentation],
								  kAFCacheContentLengthFileAttribute,
								  &realContentLength,
								  sizeof(realContentLength),
								  0, 0);
	if (sizeof(realContentLength) != size )
	{
        AFLog(@"Could not get content lenth attribute from file %@. This may be bad (errno = %ld",
              [self.cache filePathForURL:self.url], (long)errno );
        return 0LL;
    }
	
    return realContentLength;
}

- (NSString *)filename {
	return [cache filenameForURL: url];
}

- (NSString *)asString {
	if (self.data == nil) return nil;
	return [[[NSString alloc] initWithData: self.data encoding: NSUTF8StringEncoding] autorelease];
}

- (NSString*)description {
	NSMutableString *s = [NSMutableString stringWithString:@"URL: "];
	[s appendString:[url absoluteString]];
	[s appendString:@", "];
	[s appendFormat:@"tag: %d", tag];
	[s appendString:@", "];
	[s appendFormat:@"cacheStatus: %d", cacheStatus];
	[s appendString:@", "];
	[s appendFormat:@"body content size: %d\n", [self.data length]];
	[s appendString:[info description]];
	[s appendString:@"\n"];
	
	return s;
}

- (BOOL)isCachedOnDisk {
	return [cache.cacheInfoStore objectForKey: [url absoluteString]] != nil;
}

- (NSString*)guessContentType {
	NSString *extension = [[cache filenameForURL:url] stringByRegex:@".*\\." substitution:@"."];
	NSString *type = [cache.suffixToMimeTypeMap valueForKey:extension];
	return type;
}

- (NSString*)mimeType {
	if (!info.mimeType) {
		return [self guessContentType];
	}
	
	return @"";
}

- (NSString*)filePath
{
    return [self.cache filePathForURL:self.url];
}

#ifdef USE_TOUCHXML
- (CXMLDocument *)asXMLDocument {
	if (self.data == nil) return nil;
	NSError *err = nil;
	CXMLDocument *doc = [[[CXMLDocument alloc] initWithData: self.data options: 0 error: &err] autorelease];
	return (err) ? nil : doc;
}
#endif

- (void)setTag:(int)newTag {
	tag = newTag;
}

- (int)tag {
	return tag;
}

- (BOOL)isComplete {
	return (currentContentLength >= info.contentLength)?YES:NO;
}

- (void) dealloc {
	self.cache = nil;
	[info release];
	[validUntil release];
	[error release];
	[url release];
	[data release];
	[username release];
	[password release];
	
	[super dealloc];
}

@end
