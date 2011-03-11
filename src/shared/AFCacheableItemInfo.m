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

@implementation AFCacheableItemInfo

@synthesize requestTimestamp, responseTimestamp, serverDate, lastModified, age, maxAge, expireDate, eTag, statusCode, contentLength, mimeType, responseURL;


- (void)encodeWithCoder: (NSCoder *) coder {
	[coder encodeObject: [NSNumber numberWithDouble: requestTimestamp] forKey: @"AFCacheableItemInfo_requestTimestamp"];
	[coder encodeObject: [NSNumber numberWithDouble: responseTimestamp] forKey: @"AFCacheableItemInfo_responseTimestamp"];
	[coder encodeObject: serverDate forKey: @"AFCacheableItemInfo_serverDate"];
	[coder encodeObject: lastModified forKey: @"AFCacheableItemInfo_lastModified"];
	[coder encodeObject: [NSNumber numberWithDouble: age] forKey: @"AFCacheableItemInfo_age"];
	[coder encodeObject: maxAge forKey: @"AFCacheableItemInfo_maxAge"];
	[coder encodeObject: expireDate forKey: @"AFCacheableItemInfo_expireDate"];
	[coder encodeObject: eTag forKey: @"AFCacheableItemInfo_eTag"];
	[coder encodeObject: [NSNumber numberWithUnsignedInteger:statusCode] forKey: @"AFCacheableItemInfo_statusCode"];
	[coder encodeObject: [NSNumber numberWithUnsignedLongLong:contentLength] forKey: @"AFCacheableItemInfo_contentLength"];
	[coder encodeObject: mimeType forKey: @"AFCacheableItemInfo_mimeType"];
	[coder encodeObject: responseURL forKey: @"AFCacheableItemInfo_responseURL"];

}

- (id)initWithCoder: (NSCoder *) coder {
	self.requestTimestamp = [[coder decodeObjectForKey: @"AFCacheableItemInfo_requestTimestamp"] doubleValue];
	self.responseTimestamp = [[coder decodeObjectForKey: @"AFCacheableItemInfo_responseTimestamp"] doubleValue];
	self.serverDate = [coder decodeObjectForKey: @"AFCacheableItemInfo_serverDate"];
	self.lastModified = [coder decodeObjectForKey: @"AFCacheableItemInfo_lastModified"];
	self.age = [[coder decodeObjectForKey: @"AFCacheableItemInfo_age"] doubleValue];
	self.maxAge = [coder decodeObjectForKey: @"AFCacheableItemInfo_maxAge"];
	self.expireDate = [coder decodeObjectForKey: @"AFCacheableItemInfo_expireDate"];
	self.eTag = [coder decodeObjectForKey: @"AFCacheableItemInfo_eTag"];
	self.statusCode = [[coder decodeObjectForKey: @"AFCacheableItemInfo_statusCode"] intValue];
	self.contentLength = [[coder decodeObjectForKey: @"AFCacheableItemInfo_contentLength"] unsignedIntValue];
	self.mimeType = [coder decodeObjectForKey: @"AFCacheableItemInfo_mimeType"];
	self.responseURL = [coder decodeObjectForKey: @"AFCacheableItemInfo_responseURL"];

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

	[super dealloc];
}

@end