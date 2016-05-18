//
//  AFDownloadOperation.m
//  AFCache
//
//  Created by Sebastian Grimme on 28.07.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import <AFCache/AFCacheableItem.h>
#import <AFCache/AFCacheableItem+FileAttributes.h>
#import <AFCache/AFCache.h>
#import "AFDownloadOperation.h"
#import "AFCache+PrivateAPI.h"
#import "AFCache_Logging.h"
#import "DateParser.h"

@interface AFDownloadOperation () <NSURLConnectionDataDelegate>
@property(nonatomic, strong) NSURLConnection *connection;
@property(nonatomic, strong) NSOutputStream *outputStream;
@end

@implementation AFDownloadOperation

- (instancetype)initWithCacheableItem:(AFCacheableItem *)cacheableItem {
    self = [super init];
    if (self) {
        _cacheableItem = cacheableItem;
        _isExecuting = NO;
        _isFinished = NO;
    }
    return self;
}

- (void)dealloc {
    [_connection cancel];
}

#pragma mark - Core NSOperation methods

- (BOOL)isConcurrent {
    // I don't want NSOperationQueue to spawn a thread for me as my code needs to run on the main thread
    return YES;
}

- (BOOL)isAsynchronous {
    return YES;
}

- (void)start {
    
    // Do not execute cancelled operations
    if (self.isCancelled) {
        [self finish];
        return;
    }
    
    // Always perform operation on main thread as NSURLConnection wants to be started on the main thread
    if (![NSThread isMainThread])
    {
        [self performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:NO];
        return;
    }
    
    [self willChangeValueForKey:@"isExecuting"];
    _isExecuting = YES;
    [self didChangeValueForKey:@"isExecuting"];
    
    self.connection = [[NSURLConnection alloc] initWithRequest:self.cacheableItem.info.request delegate:self startImmediately:YES];
}

- (void)finish {
    [self.connection cancel];
    [self.outputStream close];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    
    [self willChangeValueForKey:@"isExecuting"];
    [self willChangeValueForKey:@"isFinished"];
    _isExecuting = NO;
    _isFinished  = YES;
    [self didChangeValueForKey:@"isFinished"];
    [self didChangeValueForKey:@"isExecuting"];
}

#pragma mark - NSURLConnectionDelegate and NSURLConnectionDataDelegate methods

/*
 * This method gives the delegate an opportunity to inspect the request that will be used to continue loading the
 * request, and modify it if necessary. The URL-change determinations mentioned above can occur as a result of
 * transforming a request URL to its canonical form, or can happen for protocol-specific reasons, such as an HTTP
 * redirect.
 */
- (NSURLRequest*)connection:(NSURLConnection*)connection willSendRequest:(NSURLRequest*)request redirectResponse:(NSURLResponse*)redirectResponse {
    NSMutableURLRequest *theRequest = [request mutableCopy];
    
    if (self.cacheableItem.cache.userAgent) {
        [theRequest setValue:self.cacheableItem.cache.userAgent forHTTPHeaderField:@"User-Agent"];
    }
    
    if (self.cacheableItem.justFetchHTTPHeader) {
        [theRequest setHTTPMethod:@"HEAD"];
    }
    
    // TODO: Check if this redirect code is fine here, it seemed broken in the original place and I corrected it as I thought it should be
    if (redirectResponse && [request URL]) {
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
- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response {
    self.cacheableItem.cache.connectedToNetwork = YES;
    
    if (self.isCancelled) {
        [self finish];
        return;
    }
    
    [self handleResponse:response];
    
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

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data {
    if (self.isCancelled) {
        [self finish];
        return;
    }
    
    if (self.outputStream.hasSpaceAvailable) {
        NSInteger bytesWritten = [self.outputStream write:data.bytes maxLength:data.length];
        if (bytesWritten != data.length) {
            [self finishWithError];
            return;
        }
    } else {
        // TODO: delegate disk full OR no access
        [self finishWithError];
        return;
    }
    
    self.cacheableItem.info.actualLength += [data length];
    [self.cacheableItem sendProgressSignalToClientItems];
}

/*
 *  The connection did finish loading. Everything should be okay at this point. If so, store object into cache and call
 *  delegate. If the server has not been delivered anything (response body is 0 bytes) we won't cache the response.
 */
- (void)connectionDidFinishLoading: (NSURLConnection *) connection {
    if (self.isCancelled) {
        [self finish];
        return;
    }
    
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
            NSError *error = nil;
            
            if (!self.cacheableItem.url) {
                error = [NSError errorWithDomain:@"URL is nil" code:99 userInfo:nil];
            }
            
            // Test for correct content length
            NSString *path = [self.cacheableItem.cache fullPathForCacheableItem:self.cacheableItem];
            NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
            if (attr) {
                uint64_t fileSize = [attr fileSize];
                if (fileSize != self.cacheableItem.info.contentLength) {
                    self.cacheableItem.info.contentLength = fileSize;
                }
            } else {
                AFLog(@"Failed to get file attributes for file at path %@. Error: %@", path, [err description]);
            }
            
            [self.cacheableItem flagAsDownloadFinishedWithContentLength:self.cacheableItem.info.contentLength];
            
            if (error) {
                AFLog(@"Error while finishing download: %@", [err localizedDescription]);
            } else {
                // Only cache response if it has a validUntil date and only if we're not in offline mode.
                if (self.cacheableItem.validUntil) {
                    AFLog(@"Updating file modification date for object with URL: %@", [self.cacheableItem.url absoluteString]);
                    [self.cacheableItem.cache updateModificationDataAndTriggerArchiving:self.cacheableItem];
                }
            }
        }
    }
    
    [self finish];
    
    BOOL hasAlreadyReturnedCacheItem = (self.cacheableItem.hasReturnedCachedItemBeforeRevalidation && self.cacheableItem.cacheStatus == kCacheStatusNotModified);
    if (!hasAlreadyReturnedCacheItem) {
        [self.cacheableItem sendSuccessSignalToClientItems];
    }
}

/*
 * The connection did fail. Remove item from cache.
 * TODO: This comment is wrong. Item is not removed from cache here. Should it be removed as the comment says?
 */

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)anError {
    if (self.isCancelled) {
        [self finish];
        return;
    }
    
    self.cacheableItem.error = anError;
    
    BOOL connectionLostOrNoConnection = ([anError code] == kCFURLErrorNotConnectedToInternet || [anError code] == kCFURLErrorNetworkConnectionLost);
    if (connectionLostOrNoConnection) {
        self.cacheableItem.cache.connectedToNetwork = NO;
    }
    else
    {
        NSLog(@"ERROR in download operation: %@", anError);
    }
    
    [self finish];
    
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
        self.cacheableItem.info.actualLength = 0;
        self.cacheableItem.currentContentLength = 0;
        [self.cacheableItem sendFailSignalToClientItems];
    }
}

- (void)finishWithError {
    [self finish];
    self.cacheableItem.info.actualLength = 0;
    self.cacheableItem.currentContentLength = 0;
    [self.cacheableItem sendFailSignalToClientItems];
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

#pragma mark - Response handling

- (void)handleResponse:(NSURLResponse *)response {
    self.cacheableItem.info.mimeType = [response MIMEType];
    
    NSDate *now = [NSDate date];
    
    self.cacheableItem.info.responseTimestamp = [now timeIntervalSinceReferenceDate];
    self.cacheableItem.info.mimeType = [response MIMEType];
    
    // Get HTTP-Status code from response
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        self.cacheableItem.info.statusCode = (NSUInteger) [(NSHTTPURLResponse *) response statusCode];
    } else {
        self.cacheableItem.info.statusCode = 200;
    }
    
    // Update modified status
    if (self.cacheableItem.cacheStatus == kCacheStatusRevalidationPending) {
        switch (self.cacheableItem.info.statusCode) {
            case 304:
                self.cacheableItem.cacheStatus = kCacheStatusNotModified;
                self.cacheableItem.validUntil = self.cacheableItem.info.expireDate;
                // The resource has not been modified, so we exit here
                return;
            case 200:
                self.cacheableItem.cacheStatus = kCacheStatusModified;
                break;
        }
    } else {
        self.cacheableItem.info.responseTimestamp = [now timeIntervalSinceReferenceDate];
        self.cacheableItem.info.response = response;
    }
    
    if (self.cacheableItem.info.statusCode == 200) {
        self.outputStream = [self.cacheableItem.cache createOutputStreamForItem:self.cacheableItem];
    }
    
    // TODO: Isn't self.cacheableItem.info.contentLength always 0 at this moment?
    [self.cacheableItem flagAsDownloadStartedWithContentLength:self.cacheableItem.info.contentLength];
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        // Handle response header fields to calculate expiration time for newly fetched object to determine until when we may cache it
        [self handleResponseHeaderFields:[(NSHTTPURLResponse *) response allHeaderFields] now:now];
    }
}

- (void)handleResponseHeaderFields:(NSDictionary *)headerFields now:(NSDate*) now {
#ifdef AFCACHE_LOGGING_ENABLED
    // log headers
    NSLog(@"status code: %d", self.cacheableItem.info.statusCode);
    for (NSString *key in [headerFields allKeys]) {
        NSString *logString = [NSString stringWithFormat: @"%@: %@", key, [headerFields objectForKey: key]];
        NSLog(@"Headers: %@", logString);
    }
#endif
    // get headers that are used for cache control
    NSString *ageField =           headerFields[@"Age"];
    NSString *dateField =          headerFields[@"Date"];
    NSString *modifiedField =      headerFields[@"Last-Modified"];
    NSString *expiresField =       headerFields[@"Expires"];
    NSString *cacheControlField =  headerFields[@"Cache-Control"];
    NSString *pragmaField =        headerFields[@"Pragma"];
    NSString *eTagField =          headerFields[@"Etag"];
    NSString *contentLengthField = headerFields[@"Content-Length"];
    
    self.cacheableItem.info.headers = headerFields;
    self.cacheableItem.info.contentLength = contentLengthField ? strtoull([contentLengthField UTF8String], NULL, 0) : 0;
    self.cacheableItem.info.eTag = eTagField;
    self.cacheableItem.info.maxAge = nil;
    
    // Parse 'Age', 'Date', 'Last-Modified', 'Expires' header field by using a date formatter capable of parsing the
    // date strings with 3 different formats (see http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3)
    self.cacheableItem.info.age = [ageField intValue];
    self.cacheableItem.info.serverDate = dateField ? [DateParser gh_parseHTTP:dateField] : now;
    NSDate *lastModifiedDate = modifiedField ? [DateParser gh_parseHTTP:modifiedField] : now;
    self.cacheableItem.info.lastModified = lastModifiedDate;
    self.cacheableItem.info.expireDate = [DateParser gh_parseHTTP:expiresField];
    
    // Check if Pragma: no-cache is set (for compatibility with HTTP/1.0 clients)
    BOOL pragmaNoCacheSet = NO;
    if (pragmaField) {
        pragmaNoCacheSet = [pragmaField rangeOfString:@"no-cache"].location != NSNotFound;
    }
    
    // Parse cache-control field (if present)
    if (cacheControlField) {
        // check if max-age is set in header fields
        NSRange range = [cacheControlField rangeOfString:@"max-age="];
        if (range.location != NSNotFound) {
            // Parse max-age (in seconds)
            unsigned long start = range.location + range.length;
            unsigned long length =  [cacheControlField length] - (range.location + range.length);
            NSString *maxAgeString = [cacheControlField substringWithRange:NSMakeRange(start, length)];
            self.cacheableItem.info.maxAge = @([maxAgeString intValue]);
        }
        
        // Check no-cache in "Cache-Control" (see http://www.ietf.org/rfc/rfc2616.txt - 14.9 Cache-Control, Page 107)
        pragmaNoCacheSet =
        ([cacheControlField rangeOfString:@"no-cache"].location != NSNotFound) ||
        [cacheControlField rangeOfString:@"no-store"].location != NSNotFound;
        
        // since AFCache can be classified as a private cache, we'll cache objects with the Cache-Control 'private' header too.
        // see 14.9.1 What is Cacheable
        // TODO: Consider all Cache-Control parameters
        /*
         cache-request-directive =
         "no-cache"                          ; Section 14.9.1
         | "no-store"                          ; Section 14.9.2
         | "max-age" "=" delta-seconds         ; Section 14.9.3, 14.9.4
         | "max-stale" [ "=" delta-seconds ]   ; Section 14.9.3
         | "min-fresh" "=" delta-seconds       ; Section 14.9.3
         | "no-transform"                      ; Section 14.9.5
         | "only-if-cached"                    ; Section 14.9.4
         | cache-extension                     ; Section 14.9.6
         
         cache-response-directive =
         "public"                               ; Section 14.9.1
         | "private" [ "=" <"> 1#field-name <"> ] ; Section 14.9.1
         | "no-cache" [ "=" <"> 1#field-name <"> ]; Section 14.9.1
         | "no-store"                             ; Section 14.9.2
         | "no-transform"                         ; Section 14.9.5
         | "must-revalidate"                      ; Section 14.9.4
         | "proxy-revalidate"                     ; Section 14.9.4
         | "max-age" "=" delta-seconds            ; Section 14.9.3
         | "s-maxage" "=" delta-seconds           ; Section 14.9.3
         | cache-extension                        ; Section 14.9.6
         */
    }
    
    // Calculate "valid until" field. The 'max-age' directive takes priority over 'Expires', takes priority over 'Last-Modified'
    BOOL mustNotCache = pragmaNoCacheSet || (self.cacheableItem.info.maxAge && [self.cacheableItem.info.maxAge intValue] == 0);
    if (mustNotCache) {
        // Do not cache as either "no-cache" or "no-store" is set or max-age is 0
        self.cacheableItem.validUntil = nil;
    } else if (self.cacheableItem.info.maxAge) {
        // Create future expire date for max age by adding the given seconds to now.
#if ((TARGET_OS_IPHONE == 0 && 1060 <= MAC_OS_X_VERSION_MAX_ALLOWED) || (TARGET_OS_IPHONE == 1 && 40000 <= __IPHONE_OS_VERSION_MAX_ALLOWED))
        self.cacheableItem.validUntil = [now dateByAddingTimeInterval: [self.cacheableItem.info.maxAge doubleValue]];
#else
        self.cacheableItem.validUntil = [now addTimeInterval: [self.cacheableItem.info.maxAge doubleValue]];
#endif
    } else if (self.cacheableItem.info.expireDate) {
        self.cacheableItem.validUntil = self.cacheableItem.info.expireDate;
    } else {
        self.cacheableItem.validUntil = lastModifiedDate;
    }
}

@end
