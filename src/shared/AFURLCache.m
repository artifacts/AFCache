/*
 *
 * Copyright 2008 Artifacts - Fine Software Development
 * http://www.artifacts.de
 * Contributed by Nico Schmidt - savoysoftware.com
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

#import "AFURLCache.h"
#import "AFCache+PrivateAPI.h"
#import "AFCacheableItem+Packaging.h"
#import "AFCache+Packaging.h"
#import "DateParser.h"

@implementation AFURLCache

-(NSCachedURLResponse*)cachedResponseForRequest:(NSURLRequest*)request
{
    NSURL* url = request.URL;
	AFCacheableItem* item = [[AFCache sharedInstance] cacheableItemFromCacheStore:url];	
	if (item && item.cacheStatus == kCacheStatusFresh) {

		/* Split content type and content encoding from the "MIME type". */

		/* TODO: Figure out a better way to parse the MIME type here. */
		NSString *mime = item.info.mimeType;
		NSString *encoding = nil;
		NSRange range = [mime rangeOfString:@"; charset="];
		if (range.length > 0) {
			encoding = [mime substringFromIndex:(range.location + 10)];
			mime = [mime substringToIndex:range.location];
		}

		NSURLResponse* response = [[NSURLResponse alloc] initWithURL:item.url 
															MIMEType:mime 
											   expectedContentLength:[item.data length]
												textEncodingName:encoding];		
		NSCachedURLResponse *cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response data:item.data userInfo:nil storagePolicy:NSURLCacheStorageAllowedInMemoryOnly];
		[response release];
        return [cachedResponse autorelease];
	} else {
		//NSLog(@"Cache miss for file: %@", [[AFCache sharedInstance] filenameForURL: url]);
	}
	
	NSCachedURLResponse *response = [super cachedResponseForRequest:request];
	return response;    
}

- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request
{
	//NSLog(@"request %@ resulted in response: %@", [request description], [cachedResponse description]);
	NSDate *lastModified = nil;
	NSDate *expireDate = nil;
	
	if ([cachedResponse.response isKindOfClass: [NSHTTPURLResponse self]]) {		
		NSDictionary *headers = [(NSHTTPURLResponse *) cachedResponse.response allHeaderFields];		
		NSString *modifiedHeader                = [headers objectForKey: @"Last-Modified"];
		NSString *expiresHeader                 = [headers objectForKey: @"Expires"];
		NSString *contentTypeHeader             = [headers objectForKey: @"Content-Type"];
		
		lastModified = (modifiedHeader) ? [DateParser gh_parseHTTP: modifiedHeader] : [NSDate date];
		expireDate	 = (expiresHeader)  ? [DateParser gh_parseHTTP: expiresHeader]  : nil;

		AFCacheableItem *item = [[AFCacheableItem alloc] initWithURL:request.URL lastModified:lastModified expireDate:expireDate contentType:contentTypeHeader];
		[[AFCache sharedInstance] importCacheableItem:item withData:cachedResponse.data];	
		[item release];
	}				
}

@end
