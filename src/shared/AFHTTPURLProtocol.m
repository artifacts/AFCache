//
//  AFHTTPURLProtocol.m
//  AFCache-iOS
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFHTTPURLProtocol.h"

@implementation AFHTTPURLProtocol

@synthesize request;

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
    [[self client] URLProtocol:self didReceiveResponse:cacheableItem.info.response cacheStoragePolicy:NSURLCacheStorageAllowed];
    [[self client] URLProtocol:self didLoadData:cacheableItem.data];
    [[self client] URLProtocolDidFinishLoading:self];    
}

- (void)stopLoading
{
   [[AFCache sharedInstance] cancelAsynchronousOperationsForURL:[[self request] URL] itemDelegate:self];
}

- (void)dealloc {
    [m_request release];
    [super dealloc];
}

@end
