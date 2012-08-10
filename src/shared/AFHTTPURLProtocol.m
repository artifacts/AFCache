//
//  AFHTTPURLProtocol.m
//  AFCache-iOS
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

/*
 *
 * Copyright 2012 artifacts Software GmbH & Co. KG
 * http://www.artifacts.de
 * Author: Michael Markowski (m.markowski@artifacts.de)
 * Many thanks to Rob Napier's excellent post about using NSURLProtocol
 * instead of NSURLCache for WebView offline caching:
 * http://robnapier.net/blog/offline-uiwebview-nsurlprotocol-588/
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
 */
 
#import "AFHTTPURLProtocol.h"

@implementation AFHTTPURLProtocol

@synthesize request = m_request;

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    if ([[[request URL] scheme] isEqualToString:@"http"] &&
        [request valueForHTTPHeaderField:AFCachingURLHeader] == nil &&
        [request valueForHTTPHeaderField:AFCacheInternalRequestHeader] == nil)        
    {
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    return request;
}

- (id)initWithRequest:(NSURLRequest *)aRequest
       cachedResponse:(NSCachedURLResponse *)cachedResponse
               client:(id <NSURLProtocolClient>)client
{
    // Modify request so we don't loop
    NSMutableURLRequest *myRequest = [aRequest mutableCopy];
    [myRequest setValue:@"" forHTTPHeaderField:AFCachingURLHeader];
    
    self = [super initWithRequest:myRequest
                   cachedResponse:cachedResponse
                           client:client];
    
    if (self)
    {
        [self setRequest:myRequest];
    }
    [myRequest release];
    return self;
}

- (void)startLoading
{
    [[AFCache sharedInstance] cachedObjectForRequest:self.request delegate:self];
}

- (void) connectionDidFail: (AFCacheableItem *) cacheableItem {
    [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]];    
}

- (void) connectionDidFinish: (AFCacheableItem *) cacheableItem {
    NSAssert(cacheableItem.info.response != nil, @"Response must not be nil - this is a software bug");
    if (cacheableItem.info.redirectRequest && cacheableItem.info.redirectResponse) {
        // for some reason this does not work when in flight mode...
        NSURLRequest *redirectRequest = cacheableItem.servedFromCache && !cacheableItem.URLInternallyRewritten ? self.request : cacheableItem.info.redirectRequest;
        NSURLResponse *redirectResponse = cacheableItem.info.redirectResponse;
        [[self client] URLProtocol:self wasRedirectedToRequest:redirectRequest redirectResponse:redirectResponse];
    } else {
        [[self client] URLProtocol:self didReceiveResponse:cacheableItem.info.response cacheStoragePolicy:NSURLCacheStorageAllowed];
        [[self client] URLProtocol:self didLoadData:cacheableItem.data];
        [[self client] URLProtocolDidFinishLoading:self];
    }
}

- (void)connectionHasBeenRedirected: (AFCacheableItem*) cacheableItem {
    // don't inform client right now, but when finished downloading. Otherwise the response will not come back to AFCache...
}

- (void)stopLoading
{
   [[AFCache sharedInstance] cancelAsynchronousOperationsForURL:[[self request] URL] itemDelegate:self];
}

- (NSCachedURLResponse *)cachedResponse {
    return [super cachedResponse];
}

- (void)dealloc {
    [m_request release];
    [super dealloc];
}

@end
