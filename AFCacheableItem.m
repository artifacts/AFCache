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
@synthesize info, validUntil, cacheStatus;

- (id) init {
	self = [super init];
	if (self != nil) {
		data = [[NSMutableData alloc] init];
		persistable = true;
		connectionDidFinishSelector = @selector(connectionDidFinish:);
		connectionDidFailSelector = @selector(connectionDidFail:);
		self.cacheStatus = kCacheStatusNew;
		self.info = [AFCacheableItemInfo new];		
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
	self.info.responseTimestamp = [now timeIntervalSinceReferenceDate];
	
	// Get HTTP-Status code from response
	int statusCode = 200;
	if ([response respondsToSelector:@selector(statusCode)]) {
		statusCode = (int)[response performSelector:@selector(statusCode)];
	}
	
	// The resource has not been modified, so we call connectionDidFinishLoading and exit here.
	if (self.cacheStatus==kCacheStatusRevalidationPending && statusCode==304) {
		self.cacheStatus=kCacheStatusNotModified;
		self.validUntil = info.expireDate;
		[self connectionDidFinishLoading: connection];
		return;
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
	
	if (validUntil) {
		NSLog(@"Setting info for Object at %@ to %@", [url absoluteString], [info description]);
		[cache.cacheInfoStore setObject: info forKey: url];
	}
	
}

- (void)connectionDidFinishLoading: (NSURLConnection *) connection {
	NSError *err = nil;
	if ([self.data length] == 0) err = [NSError errorWithDomain: @"Request returned no data" code: 99 userInfo: nil];
	if (url == nil) err = [NSError errorWithDomain: @"URL is nil" code: 99 userInfo: nil];
	if (err != nil) {
		NSLog(@"Error: %@", [err localizedDescription]);
	}
	else {
		if (delegate && [delegate respondsToSelector: connectionDidFinishSelector]) {
			[delegate performSelector: connectionDidFinishSelector withObject: self];
		}
		if (validUntil) {
#ifdef AFCACHE_LOGGING_ENABLED
			NSLog(@"Storing: %@", [self asString]);
#endif
			[(AFCache *)self.cache setObject: self forURL: url];
		}
	}
	[cache removeReferenceToConnection: connection];
}

- (void)connection: (NSURLConnection *) connection didFailWithError: (NSError *) anError;
{
	[cache removeReferenceToConnection: connection];
	self.error = anError;
	[cache.cacheInfoStore removeObjectForKey:url];
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
	//#ifdef ENABLE_ALWAYS_DO_CACHING_
	//    // If no network is available: A Cached element is always fresh!
	//    if ( ![[AFCache sharedInstance] isConnectedToNetwork] )
	//    { return YES; }
	//#endif
	
	NSTimeInterval apparent_age = fmax(0, info.responseTimestamp - [info.serverDate timeIntervalSinceReferenceDate]);
	NSTimeInterval corrected_received_age = fmax(apparent_age, info.age);
	NSTimeInterval response_delay = info.responseTimestamp - info.requestTimestamp;
	NSTimeInterval corrected_initial_age = corrected_received_age + response_delay;
	NSTimeInterval resident_time = [NSDate timeIntervalSinceReferenceDate] - info.responseTimestamp;
	NSTimeInterval current_age = corrected_initial_age + resident_time;
	
	
	NSTimeInterval freshness_lifetime = 0;
	if (info.maxAge) {
		freshness_lifetime = [info.maxAge doubleValue];
	}
	if (info.expireDate) {
		freshness_lifetime = [info.expireDate timeIntervalSinceReferenceDate] - [info.serverDate timeIntervalSinceReferenceDate];
	}
	
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

- (UIImage *)asImage {
	if (self.data == nil) return nil;
	UIImage *img = [[[UIImage alloc] initWithData: self.data] autorelease];
	return img;
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