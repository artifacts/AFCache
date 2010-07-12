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
#import "AFCache.h"

@implementation AFURLCache

-(NSCachedURLResponse*)cachedResponseForRequest:(NSURLRequest*)request
{
    NSURL* url = request.URL;
    if (![[AFCache sharedInstance] hasCachedItemForURL:url])
    {
#ifdef AFCACHE_LOGGING_ENABLED
		NSLog(@"cachedResponseForRequest: %@", [request description]);
#endif
		NSCachedURLResponse *response = [super cachedResponseForRequest:request];
        return response;
    }
    
    AFCacheableItem* item = [[AFCache sharedInstance] cachedObjectForURL:url options:0];
    if (nil == item)
    {
        return nil;
    }
    
    NSData* data = item.data;
    NSURLResponse* response = [[NSURLResponse alloc] initWithURL:url 
														MIMEType:item.mimeType 
										   expectedContentLength:[data length] textEncodingName:nil];

    return [[NSCachedURLResponse alloc] initWithResponse:response data:data];
}

- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request
{
	// TODO: put response into cache
	// find out how implicit requests initiated by html references (e.g. <img>) could be cached.
	// Although cachedResponseForRequest: is called, storeCachedResponse:forRequest: is not called
	// for implicit requests.
#ifdef AFCACHE_LOGGING_ENABLED	
	NSLog(@"request %@ resulted in response: %@", [request description], [cachedResponse description]);
#endif
}

@end
