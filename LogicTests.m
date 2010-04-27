//
//  LogicTests.m
//  AFCache
//
//  Created by Michael Markowski on 21.04.10.
//  Copyright 2010 Artifacts. All rights reserved.
//

#import "LogicTests.h"

static NSString *kBaseURL = @"http://10.10.73.140/~mic/afcache/";

@implementation LogicTests

@synthesize item;

- (void) setUp {
	// setting up an autorelease pool is necessary, otherwise
	// asynchronous requests will not return
	pool = [[NSAutoreleasePool alloc] init];
	[[AFCache sharedInstance] invalidateAll];
}

- (void) tearDown {
//	[pool release];
}

/*
   - (void) testSyncRequest {
        NSURL * url = [NSURL URLWithString:[NSString stringWithFormat:@"%@test.php", kBaseURL]];
        AFCacheableItem *item = [[AFCache sharedInstance] cachedObjectForURL:url options:0];
        STAssertNotNil(item, @"requested item must not be nil.");
        STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew'");
        [NSThread sleepForTimeInterval:1];
        item = [[AFCache sharedInstance] cachedObjectForURL:url options:0];
        STAssertNotNil(item, @"requested item must not be nil.");
        STAssertEquals(item.cacheStatus, kCacheStatusFresh, @"Cache status should be 'kCacheStatusFresh'");
        [NSThread sleepForTimeInterval:2];
        item = [[AFCache sharedInstance] cachedObjectForURL:url options:0];
        STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew'");
        STAssertNotNil(item, @"requested item must not be nil.");
   }
 */

- (void) testAsyncRequestWithMaxAgeHeader {
	asyncRequestFinished = NO;
	NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@test.php?maxage=2", kBaseURL]];
	
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew'");
	
	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	[NSThread sleepForTimeInterval: 1];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusFresh, @"Cache status should be 'kCacheStatusFresh'");
	
	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	[NSThread sleepForTimeInterval: 2];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified'");
	
	
	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified'");
}

- (void) testAsyncRequestWithExpireHeader {
	return;
	asyncRequestFinished = NO;
	NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@test.php?expires=true", kBaseURL]];
	
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew'");
	
	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	[NSThread sleepForTimeInterval: 1];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusFresh, @"Cache status should be 'kCacheStatusFresh'");

	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	[NSThread sleepForTimeInterval: 2];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified'");

	
	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified'");
}

- (void) testAsyncRequestWithoutExpireHeader {
	return;
	asyncRequestFinished = NO;
	NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@test.php", kBaseURL]];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew'");
	
	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	[NSThread sleepForTimeInterval: 2];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified'");
	
	asyncRequestFinished = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response");
	}
	NSLog(@"Result:\n%@", [item asString]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified'");
	 
}

- (void)connectionDidFail: (AFCacheableItem *) cacheableItem {
//	self.item = cacheableItem;
	asyncRequestFinished = YES;
	STAssertFalse(NO, @"connection did fail with reason %@", [cacheableItem.error description]);
}

- (void)connectionDidFinish: (AFCacheableItem *) cacheableItem {
//	self.item = cacheableItem;
	asyncRequestFinished = YES;
}

@end