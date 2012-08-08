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

#import "AFCacheableItemInfo.h"
#import "AFCache+PrivateAPI.h"

@implementation AFCacheableItemInfo

@synthesize requestTimestamp, responseTimestamp, serverDate, lastModified, age, maxAge, expireDate, eTag, statusCode, contentLength, mimeType, responseURL;
@synthesize request = m_request;
@synthesize response = m_response;
@synthesize filename = m_filename;
@synthesize redirectRequest = m_redirectRequest;
@synthesize redirectResponse = m_redirectResponse;
@synthesize packageArchiveStatus, headers;

- (NSString*)newUniqueFilename {
    CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef strRef = CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
    NSString *uuidString = [[NSString alloc] initWithString:(NSString*)strRef];
    CFRelease(strRef);
    CFRelease(uuidRef);
    return uuidString;
}


- (id)init {
    self = [super init];
    if (self) {
        m_filename = nil;
        if ([AFCache sharedInstance].cacheWithHashname)
        {
           m_filename = [self newUniqueFilename];
        }
    }
    return self;
}

- (void)encodeWithCoder: (NSCoder *) coder {
	[coder encodeObject: [NSNumber numberWithDouble: requestTimestamp] forKey: @"requestTimestamp"];
	[coder encodeObject: [NSNumber numberWithDouble: responseTimestamp] forKey: @"responseTimestamp"];
	[coder encodeObject: serverDate forKey: @"serverDate"];
	[coder encodeObject: lastModified forKey: @"lastModified"];
	[coder encodeObject: [NSNumber numberWithDouble: age] forKey: @"age"];
	[coder encodeObject: maxAge forKey: @"maxAge"];
	[coder encodeObject: expireDate forKey: @"expireDate"];
	[coder encodeObject: eTag forKey: @"eTag"];
	[coder encodeObject: [NSNumber numberWithUnsignedInteger:statusCode] forKey: @"statusCode"];
	[coder encodeObject: [NSNumber numberWithUnsignedLongLong:contentLength] forKey: @"contentLength"];
	[coder encodeObject: mimeType forKey: @"mimeType"];
	[coder encodeObject: responseURL forKey: @"responseURL"];
	[coder encodeObject: m_request forKey: @"request"];
    [coder encodeObject: m_response forKey: @"response"];        
	[coder encodeObject: m_redirectRequest forKey: @"redirectRequest"];    
    [coder encodeObject: m_redirectResponse forKey: @"redirectResponse"];        
	[coder encodeObject: m_filename forKey: @"filename"];
	[coder encodeObject: headers forKey: @"headers"];
}

- (id)initWithCoder: (NSCoder *) coder {
	self.requestTimestamp = [[coder decodeObjectForKey: @"requestTimestamp"] doubleValue];
	self.responseTimestamp = [[coder decodeObjectForKey: @"responseTimestamp"] doubleValue];
	self.serverDate = [coder decodeObjectForKey: @"serverDate"];
	self.lastModified = [coder decodeObjectForKey: @"lastModified"];
	self.age = [[coder decodeObjectForKey: @"age"] doubleValue];
	self.maxAge = [coder decodeObjectForKey: @"maxAge"];
	self.expireDate = [coder decodeObjectForKey: @"expireDate"];
	self.eTag = [coder decodeObjectForKey: @"eTag"];
	self.statusCode = [[coder decodeObjectForKey: @"statusCode"] intValue];
	self.contentLength = [[coder decodeObjectForKey: @"contentLength"] unsignedIntValue];
	self.mimeType = [coder decodeObjectForKey: @"mimeType"];
	self.responseURL = [coder decodeObjectForKey: @"responseURL"];
	self.request = [coder decodeObjectForKey: @"request"];
	self.response = [coder decodeObjectForKey: @"response"];
	self.redirectRequest = [coder decodeObjectForKey: @"redirectRequest"];
	self.redirectResponse = [coder decodeObjectForKey: @"redirectResponse"];
	self.filename = [coder decodeObjectForKey: @"filename"];
	self.headers = [coder decodeObjectForKey: @"headers"];

	return self;
}

- (NSString*)description {
	NSMutableString *s = [NSMutableString stringWithString:@"Cache information:\n"];
	[s appendFormat:@"responseURL: %@\n", [responseURL absoluteString]];
	[s appendFormat:@"requestTimestamp: %f\n", requestTimestamp];
	[s appendFormat:@"responseTimestamp: %f\n", responseTimestamp];
	[s appendFormat:@"serverDate: %@\n", [serverDate description]];
	[s appendFormat:@"lastModified: %@\n", [lastModified description]];
	[s appendFormat:@"age: %f\n", age];
	[s appendFormat:@"maxAge: %@\n", maxAge];
	[s appendFormat:@"expireDate: %@\n", [expireDate description]];
	[s appendFormat:@"eTag: %@\n", eTag];
	[s appendFormat:@"statusCode: %d\n", statusCode];
	[s appendFormat:@"contentLength: %d\n", contentLength];
	[s appendFormat:@"mimeType: %@\n", mimeType];
    [s appendFormat:@"request: %@\n", m_request];
    [s appendFormat:@"response: %@\n", m_response];
    [s appendFormat:@"redirectRequest: %@\n", m_redirectRequest];
    [s appendFormat:@"redirectResponse: %@\n", m_redirectResponse];
    [s appendFormat:@"filename: %@\n", m_filename];
	[s appendFormat:@"packageArchiveStatus: %d\n", packageArchiveStatus];
	return s;
}

- (void) dealloc {
	[maxAge release];
	[expireDate release];
	[serverDate release];
	[eTag release];	
	[mimeType release];
	[lastModified release];
	[responseURL release];
    [m_request release];
    [m_response release];
    [m_redirectRequest release];
    [m_redirectResponse release];
    [m_filename release];
    [headers release];
    
	[super dealloc];
}

@end