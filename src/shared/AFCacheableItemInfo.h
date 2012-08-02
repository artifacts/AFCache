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

#import <Foundation/Foundation.h>

typedef enum {
    kAFCachePackageArchiveStatusUnknown = 0,
    kAFCachePackageArchiveStatusLoaded = 1,
    kAFCachePackageArchiveStatusConsumed = 2,
    kAFCachePackageArchiveStatusUnarchivingFailed = 3,
    kAFCachePackageArchiveStatusLoadingFailed = 4,
} AFCachePackageArchiveStatus;

@interface AFCacheableItemInfo : NSObject <NSCoding> {
	NSTimeInterval requestTimestamp;
	NSTimeInterval responseTimestamp;
	NSDate *serverDate;
	NSTimeInterval age;
	NSNumber *maxAge;
	NSDate *expireDate;
	NSDate *lastModified;
	NSString *eTag;
	NSUInteger statusCode;
	uint64_t contentLength;
	NSString *mimeType;
	NSURL *responseURL;

    NSURLRequest *m_request;
    NSURLResponse *m_response; 
    NSURLRequest *m_redirectRequest;
    NSURLResponse *m_redirectResponse; 
    
    NSString *m_filename;
    NSDictionary *headers;
    AFCachePackageArchiveStatus    packageArchiveStatus;
}

@property (nonatomic, assign) NSTimeInterval requestTimestamp;
@property (nonatomic, assign) NSTimeInterval responseTimestamp;

@property (nonatomic, retain) NSDate *lastModified;
@property (nonatomic, retain) NSDate *serverDate;
@property (nonatomic, assign) NSTimeInterval age;
@property (nonatomic, copy) NSNumber *maxAge;
@property (nonatomic, retain) NSDate *expireDate;
@property (nonatomic, copy) NSString *eTag;
@property (nonatomic, assign) NSUInteger statusCode;
@property (nonatomic, assign) uint64_t contentLength;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, retain) NSDictionary *headers;
@property (nonatomic, retain) NSURL *responseURL; // may differ from url when redirection or URL rewriting has occured. nil if URL has not been modified.

@property (nonatomic, retain) NSURLRequest *request;
@property (nonatomic, retain) NSURLResponse *response;
@property (nonatomic, retain) NSURLRequest *redirectRequest;
@property (nonatomic, retain) NSURLResponse *redirectResponse;
@property (nonatomic, retain) NSString *filename;
@property (nonatomic, assign) AFCachePackageArchiveStatus packageArchiveStatus;

@end

