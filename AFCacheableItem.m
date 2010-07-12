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
#import "AFCache+PrivateExtensions.h"
#import "AFCache.h"
#import "DateParser.h"

@implementation AFCacheableItem

@synthesize url, data, mimeType, persistable, ignoreErrors;
@synthesize cache, delegate, connectionDidFinishSelector, connectionDidFailSelector, error;
@synthesize info, validUntil, cacheStatus, loadedFromOfflineCache, tag, userData;

- (id) init {
	self = [super init];
	if (self != nil) {
		data = [[NSMutableData alloc] init];
		persistable = true;
		connectionDidFinishSelector = @selector(connectionDidFinish:);
		connectionDidFailSelector = @selector(connectionDidFail:);
		self.cacheStatus = kCacheStatusNew;
		self.info = [[AFCacheableItemInfo alloc] init];
	}
	return self;
}

- (void)connection: (NSURLConnection *) connection didReceiveData: (NSData *) receivedData {
	[self.data appendData: receivedData];
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
 * TODO: read only the file date instead of loading the object into memory
 */
- (void)connection: (NSURLConnection *) connection didReceiveResponse: (NSURLResponse *) response {
	self.mimeType = [response MIMEType];
	BOOL mustNotCache = NO;
	NSDate *now = [NSDate date];
	NSDate *newLastModifiedDate = now;
	
//	if (info==nil) {
//		NSLog(@"AFCache internal inconsistency (connection:didReceiveResponse): Info must not be nil");
//	}
	NSAssert(info!=nil, @"AFCache internal inconsistency (connection:didReceiveResponse): Info must not be nil");
	// Get HTTP-Status code from response
	NSUInteger statusCode = 200;
	if ([response respondsToSelector:@selector(statusCode)]) {
		statusCode = (NSUInteger)[response performSelector:@selector(statusCode)];
	}
	
	// The resource has not been modified, so we call connectionDidFinishLoading and exit here.
	if (self.cacheStatus==kCacheStatusRevalidationPending) {
		if (statusCode==304) {
			self.cacheStatus = kCacheStatusNotModified;
			self.validUntil = info.expireDate;
			[self connectionDidFinishLoading: connection];
			return;
		} else if (statusCode==200) {			
			self.cacheStatus = kCacheStatusModified;
		}
	} else {
		self.info.responseTimestamp = [now timeIntervalSinceReferenceDate];
	}

	[self.data setLength: 0];

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
		NSString *cacheControlHeader			= [headers objectForKey: @"Cache-Control"];
		NSString *pragmaHeader                  = [headers objectForKey: @"Pragma"];				
		NSString *eTagHeader					= [headers objectForKey: @"Etag"];				
		
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
			NSRange range = [cacheControlHeader rangeOfString: @"no-cache"];
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
				int start = range.location + range.length;
				int length =  [cacheControlHeader length] - (range.location + range.length);
				NSString *numStr = [cacheControlHeader substringWithRange: NSMakeRange(start, length)];
				self.info.maxAge = [NSNumber numberWithInt: [numStr intValue]];
				// create future expire date for max age by adding the given seconds to now
				self.validUntil = [now addTimeInterval: [info.maxAge doubleValue]];
			}
		}
		
		// If expires is given, adjust validUntil date
		if (info.expireDate) self.validUntil = info.expireDate;		
				
		// if either "Pragma: no-cache" is set in the header, or max-age=0 is set then
		// this resource must not be cached.		
		mustNotCache = pragmaNoCacheSet || maxAgeIsSet && maxAgeIsZero;		
		if (mustNotCache) self.validUntil = nil;
	}							
	
	if (validUntil && !loadedFromOfflineCache) {
#ifdef AFCACHE_LOGGING_ENABLED
		NSLog(@"Setting info for Object at %@ to %@", [url absoluteString], [info description]);
#endif
		NSAssert(info!=nil, @"AFCache internal inconsistency (connection:didReceiveResponse): Info must not be nil");
//		if (info==nil) {			
//			NSLog(@"AFCache internal inconsistency (connection:connectionDidFinishLoading:): Info must not be nil");
//		} else {			
		[cache.cacheInfoStore setObject: info forKey: [url absoluteString]];
//		}
	}
}

/*
 *	The connection did finish loading. Everything should be okay at this point.
 *  If so, store object into cache and call delegate.
 *  If the server has not been delivered anything (response body is 0 bytes)
 *  we won't cache the response.
 */
- (void)connectionDidFinishLoading: (NSURLConnection *) connection {
	NSError *err = nil;
	if ([self.data length] == 0) err = [NSError errorWithDomain: @"Request returned no data" code: 99 userInfo: nil];
	if (url == nil) err = [NSError errorWithDomain: @"URL is nil" code: 99 userInfo: nil];
	// Log any error. Maybe someone might read it ;)
	if (err != nil) {
		NSLog(@"Error: %@", [err localizedDescription]);
	}
	else {
		// Only cache response if it has a validUntil date
		// and only if we're not in offline mode.
		if (validUntil && !loadedFromOfflineCache) {
#ifdef AFCACHE_LOGGING_ENABLED
			NSLog(@"Storing object for URL: %@", [url absoluteString]);
#endif
			// Put the object into the cache			
			[(AFCache *)self.cache setObject: self forURL: url];
		}
	}
	// Remove reference to pending connection to unlink the item from the cache
	[cache removeReferenceToConnection: connection];
	// Call delegate for this item
	if (delegate && [delegate respondsToSelector: connectionDidFinishSelector]) {
		[delegate performSelector: connectionDidFinishSelector withObject: self];
	}
}

/*
 *	The connection did fail. Remove object info from cache and call delegate.
 */
- (void)connection: (NSURLConnection *) connection didFailWithError: (NSError *) anError;
{
	[cache removeReferenceToConnection: connection];
	self.error = anError;
	[cache.cacheInfoStore removeObjectForKey:[url absoluteString]];
	if (delegate && [delegate respondsToSelector: connectionDidFailSelector]) {
		[self.delegate performSelector: connectionDidFailSelector withObject: self];
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
	NSAssert(info!=nil, @"AFCache internal inconsistency detected while validating freshness. AFCacheableItem's info object must not be nil. This is a software bug.");
	NSTimeInterval apparent_age = fmax(0, info.responseTimestamp - [info.serverDate timeIntervalSinceReferenceDate]);
	NSTimeInterval corrected_received_age = fmax(apparent_age, info.age);
	NSTimeInterval response_delay = info.responseTimestamp - info.requestTimestamp;
	NSAssert(response_delay >= 0, @"response_delay must never be negative!");
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
#ifdef AFCACHE_LOGGING_ENABLED
	NSLog(@"freshness_lifetime: %@", [NSDate dateWithTimeIntervalSinceReferenceDate: freshness_lifetime]);
	NSLog(@"current_age: %@", [NSDate dateWithTimeIntervalSinceReferenceDate: current_age]);
#endif
	return fresh;
}

- (NSString *)filename {
	return [cache filenameForURL: url];
}

#ifdef USE_TOUCHXML
- (CXMLDocument *)asXMLDocument {
	if (self.data == nil) return nil;
	NSError *err = nil;
	CXMLDocument *doc = [[[CXMLDocument alloc] initWithData: self.data options: 0 error: &err] autorelease];
	return (err) ? nil : doc;
}

#endif

- (NSString *)asString {
	if (self.data == nil) return nil;
	return [[[NSString alloc] initWithData: self.data encoding: NSUTF8StringEncoding] autorelease];
}

- (NSString*)description {
	NSMutableString *s = [NSMutableString stringWithString:@"Item information:\n"];
	[s appendString:@"URL: "];
	[s appendString:[url absoluteString]];
	[s appendString:@"\n"];
	[s appendFormat:@"tag: %d", tag];
	[s appendString:@"\n"];
	[s appendFormat:@"cacheStatus: %d", cacheStatus];
	[s appendString:@"\n"];
	[s appendFormat:@"Body content size: %d\n", [data length]];
	[s appendString:@"Body:\n"];
	[s appendString:@"\n------------------------\n"];
//	[s appendString:[self asString]];
	[s appendString:@"\n------------------------\n"];
	[s appendString:[info description]];
	[s appendString:@"\n******************************************************************\n"];	
	return s;
}

- (BOOL)isCachedOnDisk {
	return [cache.cacheInfoStore objectForKey: [url absoluteString]] != nil;
}

- (void) dealloc {
	cache = nil;
	[info release];
	[validUntil release];
	[delegate release];
	[error release];
	[url release];
	[data release];
	[mimeType release];
	[super dealloc];
}

@end