//
//  LogicTests.m
//  AFCache
//
//  Created by Michael Markowski on 21.04.10.
//  Copyright 2010 Artifacts. All rights reserved.
//

#import "LogicTests.h"
#import "AFCache+PrivateAPI.h"

static NSString *kBaseURL = @"http://localhost/~mic/afcache/";

@implementation LogicTests

@synthesize item;

- (void) setUp {
	// setting up an autorelease pool is necessary, otherwise
	// asynchronous requests will not return
	pool = [[NSAutoreleasePool alloc] init];
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
	[[AFCache sharedInstance] invalidateAll];
	[[AFCache sharedInstance] reinitialize];
	
	asyncRequestFinished_1 = NO;
	NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@test.php?maxage=5", kBaseURL]];
	
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	self.item.tag = 1;
	while (asyncRequestFinished_1 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response (Test testAsyncRequestWithMaxAgeHeader:#1)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew' (Test testAsyncRequestWithMaxAgeHeader:#1)");
	
	asyncRequestFinished_2 = NO;
	[NSThread sleepForTimeInterval: 1];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_2 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response (Test testAsyncRequestWithMaxAgeHeader:#2)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusFresh, @"Cache status should be 'kCacheStatusFresh' (Test testAsyncRequestWithMaxAgeHeader:#2)");
	
	asyncRequestFinished_3 = NO;
	[NSThread sleepForTimeInterval: 10];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_3 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response (Test testAsyncRequestWithMaxAgeHeader:#3)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified' (Test testAsyncRequestWithMaxAgeHeader:#3)");
	
	
	asyncRequestFinished_4 = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	self.item.tag = 4;
	while (asyncRequestFinished_4 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response (Test testAsyncRequestWithMaxAgeHeader:#4)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified' (Test testAsyncRequestWithMaxAgeHeader:#4)");
}

- (void) testAsyncRequestWithExpireHeader {
	[[AFCache sharedInstance] invalidateAll];
	[[AFCache sharedInstance] reinitialize];
	
	asyncRequestFinished_1 = NO;
	NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@test.php?expires=true", kBaseURL]];
	
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	self.item.tag = 1;
	while (asyncRequestFinished_1 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithExpireHeader:#1)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew' (Test testAsyncRequestWithExpireHeader:#1)");
	
	asyncRequestFinished_2 = NO;
	[NSThread sleepForTimeInterval: 1];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_2 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithExpireHeader:#2)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusFresh, @"Cache status should be 'kCacheStatusFresh' (Test testAsyncRequestWithExpireHeader:#2)");

	asyncRequestFinished_3 = NO;
	[NSThread sleepForTimeInterval: 10];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_3 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithExpireHeader:#3)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified' (Test testAsyncRequestWithExpireHeader:#3)");

	asyncRequestFinished_4 = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	self.item.tag = 4;
	while (asyncRequestFinished_4 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test #4)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified' (Test testAsyncRequestWithExpireHeader:#4). %@", [item description]);
	
}

- (void) testAsyncRequestWithoutExpireHeader {
	[[AFCache sharedInstance] invalidateAll];
	[[AFCache sharedInstance] reinitialize];
	
	asyncRequestFinished_1 = NO;
	NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@test.php", kBaseURL]];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	self.item.tag = 1;
	while (asyncRequestFinished_1 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithoutExpireHeader:#1)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew' (Test testAsyncRequestWithoutExpireHeader:#1)");
	
	asyncRequestFinished_2 = NO;
	[NSThread sleepForTimeInterval: 2];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_2 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithoutExpireHeader:#2)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified' (Test testAsyncRequestWithoutExpireHeader:#2)");
	
	asyncRequestFinished_3 = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_3 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithoutExpireHeader:#3)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified' (Test testAsyncRequestWithoutExpireHeader:#3)");
	 
}

- (void) testAsyncRequestWithExpireHeaderOffline {
	[[AFCache sharedInstance] invalidateAll];
	[[AFCache sharedInstance] reinitialize];
	
	asyncRequestFinished_1 = NO;
	NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"%@test.php?expires=true", kBaseURL]];
	
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	self.item.tag = 1;
	while (asyncRequestFinished_1 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithExpireHeaderOffline:#1)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusNew, @"Cache status should be 'kCacheStatusNew' (Test testAsyncRequestWithExpireHeaderOffline:#1)");
	
	NSLog(@"Setting cache into offline mode");
	[[AFCache sharedInstance] setOffline:YES];
	asyncRequestFinished_2 = NO;
	[NSThread sleepForTimeInterval: 1];
	AFCacheableItem *cachedItem = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_2 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithExpireHeaderOffline:#2)");
	}
	NSLog(@"Result:\n%@", [cachedItem description]);
	STAssertNotNil(cachedItem, @"requested item must not be nil.");
	STAssertEquals(cachedItem.cacheStatus, kCacheStatusFresh, @"Cache status should be 'kCacheStatusFresh' (Test testAsyncRequestWithExpireHeaderOffline:#2)");
	STAssertEquals(cachedItem.loadedFromOfflineCache, YES, @"loadedFromOfflineCache should be 'YES' (Test testAsyncRequestWithExpireHeaderOffline:#2)");

	STAssertEquals([[cachedItem asString] hash] , [[item asString] hash], @"the cached response body (data)  must be equal to the original response body (Test testAsyncRequestWithExpireHeaderOffline:#2)");
	STAssertEquals(cachedItem.loadedFromOfflineCache, YES, @"loadedFromOfflineCache should be 'YES' (Test testAsyncRequestWithExpireHeaderOffline:#2)");
	
	NSLog(@"Setting cache into back into online mode");
	[[AFCache sharedInstance] setOffline:NO];	
	asyncRequestFinished_3 = NO;
	[NSThread sleepForTimeInterval: 10];
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	while (asyncRequestFinished_3 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test testAsyncRequestWithExpireHeader:#3)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.loadedFromOfflineCache, NO, @"loadedFromOfflineCache should be 'NO' (Test testAsyncRequestWithExpireHeaderOffline:#3)");
	STAssertEquals(item.cacheStatus, kCacheStatusNotModified, @"Cache status should be 'kCacheStatusNotModified' (Test testAsyncRequestWithExpireHeaderOffline:#3)");
	
	NSLog(@"Setting cache into offline mode");
	[[AFCache sharedInstance] setOffline:YES];	
	asyncRequestFinished_4 = NO;
	self.item = [[AFCache sharedInstance] cachedObjectForURL: url delegate: self];
	self.item.tag = 4;
	while (asyncRequestFinished_4 == NO) {
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
		NSLog(@"waiting for HTTP response  (Test #4)");
	}
	NSLog(@"Result:\n%@", [item description]);
	STAssertNotNil(item, @"requested item must not be nil.");
	STAssertEquals(item.cacheStatus, kCacheStatusFresh, @"Cache status should be 'kCacheStatusFresh' (Test testAsyncRequestWithExpireHeaderOffline:#4). %@", [item description]);
	STAssertEquals(item.loadedFromOfflineCache, YES, @"loadedFromOfflineCache should be 'YES' (Test testAsyncRequestWithExpireHeaderOffline:#2)");
	
}



- (void)connectionDidFail: (AFCacheableItem *) cacheableItem {
	[self setFinishedForItem:cacheableItem];	
	STAssertFalse(NO, @"connection did fail with reason %@", [cacheableItem.error description]);
}

- (void)connectionDidFinish: (AFCacheableItem *) cacheableItem {
//	NSLog(@"connectionDidFinish for item: %@", [item description]);
	[self setFinishedForItem:cacheableItem];
}

- (void)setFinishedForItem:(AFCacheableItem*)anItem {
	switch (anItem.tag) {
		case 1:
			asyncRequestFinished_1 = YES;
			break;
		case 2:
			asyncRequestFinished_2 = YES;
			break;
		case 3:
			asyncRequestFinished_3 = YES;
			break;
		case 4:
			asyncRequestFinished_4 = YES;			
			break;
	}
}
@end