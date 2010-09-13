//
//  TestController.m
//  AFCache
//
//  Created by neonico on 8/12/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "TestController.h"
#import "AFCache.h"
#import "TestController.h"


@implementation TestController



- (void)fetchFile
{
    AFCache* cache = [AFCache sharedInstance];
    [cache cachedObjectForURL:[NSURL URLWithString:@"http://localhost:49000/file?numBytes=100&delay=0.5&blockSize=10"]
                     delegate:self
                     selector:@selector(didLoad:)
                      options:0];
}



- (void)test
{
    AFCache* cache = [AFCache sharedInstance];
    [cache invalidateAll];

    [NSTimer scheduledTimerWithTimeInterval:0.4
                                     target:self
                                   selector:@selector(fetchFile)
                                   userInfo:nil
                                    repeats:YES];
}



- (void)didLoad:(AFCacheableItem*)item
{
    NSLog(@"item did load %@", item.url);
}



@end
