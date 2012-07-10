//
//  AFCacheTests.m
//  AFCacheTests
//
//  Created by Michael Markowski on 11.03.11.
//  Copyright 2011 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCacheTests.h"
#import "AFCache.h"
#import "AFCacheableItem.h"

@implementation AFCacheTests

- (void)setUp
{
    [super setUp];
            
}

- (void)tearDown
{
    // wait until archiving has been finished (default is 5s)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:8.0]];    
    
    [super tearDown];
}

- (void)testCacheableItemBlocks_Success
{
    __block BOOL requestHandled = NO;
    __block BOOL success = NO;
    
    [[AFCache sharedInstance] cachedObjectForURL:[NSURL URLWithString:@"http://localhost/~mic/artifacts/img/images/af-base.png"]
                                 completionBlock: ^(AFCacheableItem* item) {
                                     NSLog(@"completed. item: %@", item);
                                     requestHandled = YES;
                                     success = YES;
                                 }
                                       failBlock: ^(AFCacheableItem* item) {
                                           NSLog(@"failed. item: %@", item);                                           
                                           requestHandled = YES;                                           
                                       }
                                   progressBlock: ^(AFCacheableItem* item) {
                                       NSLog(@"progress. item: %@", item);                                       
                                   }
                                         options: 0];
    
    while (!requestHandled)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    STAssertTrue(success, @"The request should have failed but did not - so the test fails.");
}

- (void)ttttestCacheableItemBlocks_Fail
{
    __block BOOL requestHandled = NO;
    __block BOOL failed = NO;
    
    [[AFCache sharedInstance] cachedObjectForURL:[NSURL URLWithString:@"http://localhost/failed"]
                                 completionBlock: ^(AFCacheableItem* item) {
                                     NSLog(@"completed. item: %@", item);
                                     requestHandled = YES;
                                 }
                                       failBlock: ^(AFCacheableItem* item) {
                                           NSLog(@"failed. item: %@", item);                                           
                                           requestHandled = YES;
                                           failed = YES;
                                       }
                                   progressBlock: ^(AFCacheableItem* item) {
                                       NSLog(@"progress. item: %@", item);                                       
                                   }
                                         options: 0];
    
    while (!requestHandled)
    {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    STAssertTrue(failed, @"The request should have failed but did not - so the test fails.");
}

@end
