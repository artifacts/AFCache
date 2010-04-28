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


@interface AFCacheableItemInfo : NSObject <NSCoding> {
	NSTimeInterval requestTimestamp;
	NSTimeInterval responseTimestamp;
	NSDate *serverDate;
	NSTimeInterval age;
	NSNumber *maxAge;
	NSDate *expireDate;
	NSDate *lastModified;
}

@property (nonatomic, assign) NSTimeInterval requestTimestamp;
@property (nonatomic, assign) NSTimeInterval responseTimestamp;

@property (nonatomic, retain) NSDate *lastModified;
@property (nonatomic, retain) NSDate *serverDate;
@property (nonatomic, assign) NSTimeInterval age;
@property (nonatomic, copy) NSNumber *maxAge;
@property (nonatomic, retain) NSDate *expireDate;

@end