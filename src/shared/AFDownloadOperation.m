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
#import "AFCache+PrivateAPI.h"
#import "AFCache_Logging.h"

@interface AFDownloadOperation () <NSURLConnectionDataDelegate>

@property(nonatomic, assign) BOOL executing;
@property(nonatomic, assign) BOOL finished;

@property(nonatomic, strong) NSURLConnection *connection;

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

    // TODO: Check if this redirect code is fine here, it seemed broken in the original place and I corrected it as I thought it should be
    if (redirectResponse && [request URL]) {
        //[theRequest setURL:[redirectResponse URL]];

        self.cacheableItem.info.responseURL = [request URL];
        self.cacheableItem.info.redirectRequest = request;
        self.cacheableItem.info.redirectResponse = redirectResponse;

        // TODO: Do not access #urlRedirects directly but provide access method
        [self.cacheableItem.cache.urlRedirects setValue:[self.cacheableItem.info.responseURL absoluteString] forKey:[self.cacheableItem.url absoluteString]];
    }

    return theRequest;
}

/*
 * This method is called when the server has determined that it has enough information to create the NSURLResponse it
 * can be called multiple times, for example in the case of a redirect, so each time we reset the data.
 *
 * After the response headers are parsed, we try to load the object from disk. If the cached object is fresh, we call
 * connectionDidFinishLoading: with the cached object and cancel the original request. If the object is stale, we go on
 * with the request.
 */

- (void)connection: (NSURLConnection *) connection didReceiveResponse: (NSURLResponse *) response {
    self.cacheableItem.cache.connectedToNetwork = YES;

    [self.cacheableItem handleResponse:response];

    // call didFailSelector when statusCode >= 400
    if (self.cacheableItem.cache.failOnStatusCodeAbove400 && self.cacheableItem.info.statusCode >= 400) {
        [self connection:connection didFailWithError:[NSError errorWithDomain:kAFCacheNSErrorDomain code:self.cacheableItem.info.statusCode userInfo:nil]];
        return;
    }

    if (self.cacheableItem.validUntil) {
        // TODO: Do not expose #cachedItemInfos directly but provide access method
        [self.cacheableItem.cache.cachedItemInfos setObject: self.cacheableItem.info forKey: [self.cacheableItem.url absoluteString]];
    }

    if (self.cacheableItem.justFetchHTTPHeader) {
        [self connectionDidFinishLoading:connection];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    // Append data to the end of download file
    [self.cacheableItem.fileHandle seekToEndOfFile];
    [self.cacheableItem.fileHandle writeData:data];
    self.cacheableItem.info.actualLength += [data length];

    [self.cacheableItem sendProgressSignalToClientItems];
}

/*
 *  The connection did finish loading. Everything should be okay at this point. If so, store object into cache and call
 *  delegate. If the server has not been delivered anything (response body is 0 bytes) we won't cache the response.
 */
- (void)connectionDidFinishLoading: (NSURLConnection *) connection {
    switch (self.cacheableItem.info.statusCode) {
        case 204: // No Content
        case 205: // Reset Content
            // TODO: case 206: Partial Content
        case 400: // Bad Request
        case 401: // Unauthorized
        case 402: // Payment Required
        case 403: // Forbidden
        case 404: // Not Found
        case 405: // Method Not Allowed
        case 406: // Not Acceptable
        case 407: // Proxy Authentication Required
        case 408: // Request Timeout
        case 409: // Conflict
        case 410: // Gone
        case 411: // Length Required
        case 412: // Precondition Failed
        case 413: // Request Entity Too Large
        case 414: // Request-URI Too Long
        case 415: // Unsupported Media Type
        case 416: // Requested Range Not Satisfiable
        case 417: // Expectation Failed
        case 500: // Internal Server Error
        case 501: // Not Implemented
        case 502: // Bad Gateway
        case 503: // Service Unavailable
        case 504: // Gateway Timeout
        case 505: // HTTP Version Not Supported
            break;

        default: {
            NSError *err = nil;

            if (!self.cacheableItem.url) {
                err = [NSError errorWithDomain:@"URL is nil" code:99 userInfo:nil];
            }

            // Test for correct content length
            NSString *path = [self.cacheableItem.cache fullPathForCacheableItem:self.cacheableItem];
            NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&err];
            if (attr) {
                uint64_t fileSize = [attr fileSize];
                if (fileSize != self.cacheableItem.info.contentLength) {
                    self.cacheableItem.info.contentLength = fileSize;
                }
            } else {
                AFLog(@"Failed to get file attributes for file at path %@. Error: %@", path, [err description]);
            }

            // TODO: Make #fileHandle become property of myself (move from AFCacheableItem)
            [self.cacheableItem setDownloadFinishedFileAttributes];
            [self.cacheableItem.fileHandle closeFile];
            self.cacheableItem.fileHandle = nil;

            if (err) {
                AFLog(@"Error while finishing download: %@", [err localizedDescription]);
            } else {
                // Only cache response if it has a validUntil date and only if we're not in offline mode.
                if (self.cacheableItem.validUntil) {
                    AFLog(@"Updating file modification date for object with URL: %@", [self.url absoluteString]);
                    [self.cacheableItem.cache updateModificationDataAndTriggerArchiving:self.cacheableItem];
                }
            }
        }
    }

    BOOL hasAlreadyReturnedCacheItem = (self.cacheableItem.hasReturnedCachedItemBeforeRevalidation && self.cacheableItem.cacheStatus == kCacheStatusNotModified);
    if (!hasAlreadyReturnedCacheItem) {
        [self.cacheableItem sendSuccessSignalToClientItems];
    }

    [self finish];

    return;
}

/*
 * The connection did fail. Remove item from cache.
 * TODO: This comment is wrong. Item is not removed from cache here. Should it be removed as the comment says?
 */

- (void)connection: (NSURLConnection *) connection didFailWithError: (NSError *) anError {
    AFLog(@"didFailWithError: %@", anError);
    [self.cacheableItem.fileHandle closeFile];
    self.cacheableItem.fileHandle = nil;

    self.cacheableItem.error = anError;

    BOOL connectionLostOrNoConnection = ([anError code] == kCFURLErrorNotConnectedToInternet || [anError code] == kCFURLErrorNetworkConnectionLost);
    if (connectionLostOrNoConnection) {
        self.cacheableItem.cache.connectedToNetwork = NO;
    }

    // There are cases when we send success, despite of the error. Requirements:
    // - We have no network connection or the connection has been lost
    // - The response status is below 400 (e.g. no 404)
    // - The item is complete (the data size on disk matches the content size in the response header)
    // - OR: Connection lost while revalidating
    BOOL sendSuccessDespiteError =
            (connectionLostOrNoConnection && self.cacheableItem.info.statusCode < 400 && self.cacheableItem.isComplete) ||
            (self.cacheableItem.isRevalidating && connectionLostOrNoConnection);
    if (sendSuccessDespiteError) {
        [self.cacheableItem sendSuccessSignalToClientItems];
    } else {
        [self.cacheableItem sendFailSignalToClientItems];
    }

    [self finish];
}

#pragma mark - NSURLConnectionDelegate authentication methods

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
