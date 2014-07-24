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

- (NSString*)newUniqueFilename {
    CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef strRef = CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
    NSString *uuidString = [[NSString alloc] initWithString:(__bridge NSString*)strRef];
    CFRelease(strRef);
    CFRelease(uuidRef);
    return uuidString;
}


- (id)init {
    self = [super init];
    if (self) {
        // TODO: We cannot assume that this item's cache is the default sharedInstance
        _filename = [AFCache sharedInstance].cacheWithHashname ? [self newUniqueFilename] : nil;
    }
    return self;
}

- (id)initWithCoder: (NSCoder *) coder {
    self = [super init];
    if (self) {
        _requestTimestamp = [[coder decodeObjectForKey:@"requestTimestamp"] doubleValue];
        _responseTimestamp = [[coder decodeObjectForKey:@"responseTimestamp"] doubleValue];
        _serverDate = [coder decodeObjectForKey:@"serverDate"];
        _lastModified = [coder decodeObjectForKey:@"lastModified"];
        _age = [[coder decodeObjectForKey:@"age"] doubleValue];
        _maxAge = [coder decodeObjectForKey:@"maxAge"];
        _expireDate = [coder decodeObjectForKey:@"expireDate"];
        _eTag = [coder decodeObjectForKey:@"eTag"];
        _statusCode = [[coder decodeObjectForKey:@"statusCode"] unsignedIntegerValue];
        _contentLength = [[coder decodeObjectForKey:@"contentLength"] unsignedIntValue];
        _mimeType = [coder decodeObjectForKey:@"mimeType"];
        _responseURL = [coder decodeObjectForKey:@"responseURL"];
        _request = [coder decodeObjectForKey:@"request"];
        _response = [coder decodeObjectForKey:@"response"];
        _redirectRequest = [coder decodeObjectForKey:@"redirectRequest"];
        _redirectResponse = [coder decodeObjectForKey:@"redirectResponse"];
        _filename = [coder decodeObjectForKey:@"filename"];
        _headers = [coder decodeObjectForKey:@"headers"];
    }

    return self;
}

- (void)encodeWithCoder: (NSCoder *) coder {
	[coder encodeObject: [NSNumber numberWithDouble: self.requestTimestamp] forKey: @"requestTimestamp"];
	[coder encodeObject: [NSNumber numberWithDouble: self.responseTimestamp] forKey: @"responseTimestamp"];
	[coder encodeObject: self.serverDate forKey: @"serverDate"];
	[coder encodeObject: self.lastModified forKey: @"lastModified"];
	[coder encodeObject: [NSNumber numberWithDouble: self.age] forKey: @"age"];
	[coder encodeObject: self.maxAge forKey: @"maxAge"];
	[coder encodeObject: self.expireDate forKey: @"expireDate"];
	[coder encodeObject: self.eTag forKey: @"eTag"];
	[coder encodeObject: [NSNumber numberWithUnsignedInteger:self.statusCode] forKey: @"statusCode"];
	[coder encodeObject: [NSNumber numberWithUnsignedLongLong:self.contentLength] forKey: @"contentLength"];
	[coder encodeObject: self.mimeType forKey: @"mimeType"];
	[coder encodeObject: self.responseURL forKey: @"responseURL"];
	[coder encodeObject: self.request forKey: @"request"];
    [coder encodeObject: self.response forKey: @"response"];
	[coder encodeObject: self.redirectRequest forKey: @"redirectRequest"];
    [coder encodeObject: self.redirectResponse forKey: @"redirectResponse"];
	[coder encodeObject: self.filename forKey: @"filename"];
	[coder encodeObject: self.headers forKey: @"headers"];
}

- (NSString*)description {
	NSMutableString *s = [NSMutableString stringWithString:@"Cache information:\n"];
	[s appendFormat:@"responseURL: %@\n", [self.responseURL absoluteString]];
	[s appendFormat:@"requestTimestamp: %f\n", self.requestTimestamp];
	[s appendFormat:@"responseTimestamp: %f\n", self.responseTimestamp];
	[s appendFormat:@"serverDate: %@\n", [self.serverDate description]];
	[s appendFormat:@"lastModified: %@\n", [self.lastModified description]];
	[s appendFormat:@"age: %f\n", self.age];
	[s appendFormat:@"maxAge: %@\n", self.maxAge];
	[s appendFormat:@"expireDate: %@\n", [self.expireDate description]];
	[s appendFormat:@"eTag: %@\n", self.eTag];
	[s appendFormat:@"statusCode: %ld\n", (long)self.statusCode];
	[s appendFormat:@"expectedContentLength: %ld\n", (long)self.contentLength];
	[s appendFormat:@"currentContentLength: %ld\n", (long)self.actualLength];
	[s appendFormat:@"mimeType: %@\n", self.mimeType];
    [s appendFormat:@"request: %@\n", self.request];
    [s appendFormat:@"response: %@\n", self.response];
    [s appendFormat:@"redirectRequest: %@\n", self.redirectRequest];
    [s appendFormat:@"redirectResponse: %@\n", self.redirectResponse];
    [s appendFormat:@"filename: %@\n", self.filename];
	[s appendFormat:@"packageArchiveStatus: %d\n", self.packageArchiveStatus];
	return s;
}

-(uint64_t)actualLength
{
	if(!_actualLength)
	{
		if(self.cachePath)
		{
			NSError* err = nil;
			NSDictionary* attr = [[NSFileManager defaultManager] attributesOfItemAtPath:self.cachePath error:&err];
			if (attr == nil)
			{
				return 0;
			}
			
			uint64_t fileSize = [attr fileSize];
			_actualLength = fileSize;
		}
		else
		{
			_actualLength = 0;
		}
	}
	return _actualLength;
}

@end