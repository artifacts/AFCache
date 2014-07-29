//
//  AFCacheManager.m
//  AFCache
//
//  Created by Sebastian Grimme on 29.07.14.
//  Copyright (c) 2014 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCacheManager.h"

NSString *kAFCacheDefaultName = @"AFCacheDefaultName";

static AFCacheManager *sharedAFCacheManagerInstance = nil;

@interface AFCacheManager ()
@property (nonatomic, strong) NSMutableDictionary* instanceDictionary;
@end

@implementation AFCacheManager

#pragma mark singleton methods

+ (AFCacheManager*)sharedManager {
    @synchronized(self) {
        if (sharedAFCacheManagerInstance == nil) {
            sharedAFCacheManagerInstance = [[self alloc] init];
        }
    }
    return sharedAFCacheManagerInstance;
}

#pragma mark - Lifecycle

- (instancetype)init
{
    self = [super init];
    if (self) {
        // create dictionary which holds all named cache-instances
        _instanceDictionary = [[NSMutableDictionary alloc] init];
    }
    return self;
}

#pragma mark - Private API

- (AFCache*)cacheInstanceForName:(NSString *)name
{
    @synchronized (self.instanceDictionary) {
        AFCache *cacheInstance = [[AFCacheManager sharedManager].instanceDictionary objectForKey:name];
        
        if (!cacheInstance) {
            cacheInstance = [[AFCache alloc] init];
            
            [[AFCacheManager sharedManager].instanceDictionary setObject:cacheInstance forKey:name];
        }

        return cacheInstance;
    }
}

#pragma mark - static factory/get methods

+ (AFCache*)defaultCache
{
    return [[AFCacheManager sharedManager] cacheInstanceForName:kAFCacheDefaultName];
}

+ (AFCache*)cacheForName:(NSString*)name
{
    return [[AFCacheManager sharedManager] cacheInstanceForName:name];
}

@end
