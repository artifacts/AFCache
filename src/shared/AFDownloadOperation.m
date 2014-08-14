//
//  AFDownloadOperation.m
//  AFCache
//
//  Created by Sebastian Grimme on 28.07.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import <AFCache/AFCacheableItem.h>
#import <AFCache/AFCache.h>
#import "AFDownloadOperation.h"

@interface AFDownloadOperation () <NSURLConnectionDataDelegate>

@property(nonatomic, strong) NSURLConnection *connection;
@property(nonatomic, assign) BOOL executing;
@property(nonatomic, assign) BOOL finished;

@end

@implementation AFDownloadOperation

- (instancetype)initWithCacheableItem:(AFCacheableItem *)cacheableItem {
    self = [super init];
    if (self) {
        _cacheableItem = cacheableItem;
        _executing = NO;
        _finished = NO;
    }
    return self;
}

- (void)dealloc {
    [_connection cancel];
}

- (BOOL)isConcurrent {
    // I don't want NSOperationQueue to spawn a thread for me as my code needs to run on the main thread
    return YES;
}

- (void)start {

    // Always perform operation on main thread as NSURLConnection wants to be started on the main thread
    if (![NSThread isMainThread])
    {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }

    if ([self isCancelled] || [self isFinished]) {
        [self finish];
    }

    [self willChangeValueForKey:@"isExecuting"];
    self.executing = YES;
    [self didChangeValueForKey:@"isExecuting"];

    self.connection = [[NSURLConnection alloc] initWithRequest:self.cacheableItem.info.request delegate:self];
}

- (void)finish {
    [self.connection cancel];

    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    self.executing = NO;
    self.finished  = YES;
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isExecuting {
    return self.executing;
}

- (BOOL)isFinished {
    return self.finished;
}

- (void)cancel {
    [super cancel];

    [self.connection cancel];
    self.cacheableItem.delegate = nil;
    [self.cacheableItem removeBlocks];
}

#pragma mark NSURLConnectionDelegate and NSURLConnectionDataDelegate methods

/*
 * This method gives the delegate an opportunity to inspect the request that will be used to continue loading the
 * request, and modify it if necessary. The URL-change determinations mentioned above can occur as a result of
 * transforming a request URL to its canonical form, or can happen for protocol-specific reasons, such as an HTTP
 * redirect.
 */

- (NSURLRequest *)connection: (NSURLConnection *)connection willSendRequest: (NSURLRequest *)request redirectResponse: (NSURLResponse *)redirectResponse;
{
    NSMutableURLRequest *theRequest = [request mutableCopy];

    if (self.cacheableItem.cache.userAgent) {
        [theRequest setValue:self.cacheableItem.cache.userAgent forHTTPHeaderField:@"User-Agent"];
    }

    if (self.cacheableItem.justFetchHTTPHeader) {
        [theRequest setHTTPMethod:@"HEAD"];
    }

    // TODO: Check with Michael if this redirect code is fine here, it seemed broken in the original place and I corrected it as I thought it should be
    if ([redirectResponse URL]) {
        [theRequest setURL:[redirectResponse URL]];

        self.cacheableItem.info.responseURL = [redirectResponse URL];
        self.cacheableItem.info.redirectRequest = request;
        self.cacheableItem.info.redirectResponse = redirectResponse;

        [self.cacheableItem.cache.urlRedirects setValue:[self.cacheableItem.info.responseURL absoluteString] forKey:[self.cacheableItem.url absoluteString]];
    }

    return theRequest;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.cacheableItem performSelector:_cmd withObject:connection withObject:response];

    if ((self.cacheableItem.cache.failOnStatusCodeAbove400 && self.cacheableItem.info.statusCode >= 400) || (self.cacheableItem.justFetchHTTPHeader)) {
        [self finish];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.cacheableItem performSelector:_cmd withObject:connection withObject:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.cacheableItem performSelector:_cmd withObject:connection];

    [self finish];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.cacheableItem performSelector:_cmd withObject:connection withObject:error];

    [self finish];
}

/*
 * If implemented, will be called before connection:didReceiveAuthenticationChallenge: to give the delegate a chance to
 * inspect the protection space that will be authenticated against. Delegates should determine if they are prepared to
 * respond to the authentication method of the protection space and if so, return YES, or NO to allow default processing
 * to handle the authentication.
 */
- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
    if ([[protectionSpace authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        // Server is using a SSL certificate that the OS can't validate, see whether the client settings allow validation here
        if (self.cacheableItem.cache.disableSSLCertificateValidation) {
            return YES;
        }
    }
    return self.cacheableItem.urlCredential.user && self.cacheableItem.urlCredential.password;
}

/*
 * Gets called when basic http authentication is required. Provide given username and password. If login has failed,
 * aborts the authentication.
 */
- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if ([challenge previousFailureCount] > 0) {
        // Last authentication failed, abort authentication
        [self connection:connection didCancelAuthenticationChallenge:challenge];
        return;
    }

    if (self.cacheableItem.urlCredential.user && self.cacheableItem.urlCredential.password) {
        [[challenge sender] useCredential:self.cacheableItem.urlCredential forAuthenticationChallenge:challenge];
    }

    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] && self.cacheableItem.cache.disableSSLCertificateValidation) {
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    }
    else {
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

- (void)connection:(NSURLConnection *)connection didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    NSError *err = [NSError errorWithDomain: @"HTTP Authentifcation failed" code:99 userInfo:nil];
    [self connection:connection didFailWithError:err];
}

@end
