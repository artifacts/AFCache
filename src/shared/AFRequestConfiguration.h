//
//  AFRequestConfiguration.h
//  AFCache
//
//  Created by Sebastian Grimme on 24.07.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFRequestConfiguration : NSObject

@property (nonatomic, assign) int options;
@property (nonatomic, strong) id userData;
@property (nonatomic, strong) NSURLRequest *request;

@end
