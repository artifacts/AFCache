//
//  AFRequestInfo.h
//  AFCacheTestTool
//
//  Created by Michael Markowski on 01/08/14.
//  Copyright (c) 2014 artifacts Software GmbH & Co KG. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFRequestInfo : NSObject

@property (nonatomic, strong) NSURL *requestURL;
@property (nonatomic, strong) NSDate *requestTimestamp;
@property (nonatomic, strong) NSString *requestHeader;
@property (nonatomic, strong) NSDate *responseTimestamp;
@property (nonatomic, strong) NSString *responseHeader;
@property (nonatomic, strong) NSData *responseData;
@property (nonatomic, strong) NSNumber *successful;
@property (nonatomic, strong) NSString *cacheStatus;
@property (nonatomic, strong) NSString *internalRequestType;
@property (nonatomic, strong) NSNumber *servedFromCache;
@property (nonatomic, strong) NSNumber *levelIndicatorValue;

@end
