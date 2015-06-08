//
//  AFDownloadOperation.h
//  AFCache
//
//  Created by Sebastian Grimme on 28.07.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFDownloadOperation : NSOperation

@property(nonatomic, readonly) AFCacheableItem *cacheableItem;
@property (nonatomic, readonly) BOOL isExecuting;
@property (nonatomic, readonly) BOOL isFinished;

- (instancetype)initWithCacheableItem:(AFCacheableItem*)cacheableItem;

@end
