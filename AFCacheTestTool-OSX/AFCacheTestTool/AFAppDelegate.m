//
//  AFAppDelegate.m
//  AFCacheTestTool
//
//  Created by Michael Markowski on 01/08/14.
//  Copyright (c) 2014 artifacts Software GmbH & Co KG. All rights reserved.
//

#import "AFAppDelegate.h"
#import <AFCache/AFCache.h>
#import "AFRequestInfo.h"

#define kLastURL @"lastURL"

@implementation AFAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSInteger num = [[[NSUserDefaults standardUserDefaults] valueForKey:@"numberOfRequests"] integerValue];
    if (num == 0) {
        [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInteger:1] forKey:@"numberOfRequests"];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[AFCache sharedInstance] archiveNow];    
}

- (IBAction)clearCacheAction:(id)sender {
    [[AFCache sharedInstance] invalidateAll];
    [[AFCache sharedInstance] archiveNow];
}

- (IBAction)performRequestAction:(id)sender {
    AFCache *cache = [AFCache sharedInstance];
    NSString *URLString = [self.URLTextField stringValue];
    if ([URLString length] == 0) {
        [[NSAlert alertWithMessageText:@"No URL given" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Please provide an URL"] runModal];
        return;
    }
    NSURL *URL = [NSURL URLWithString:URLString];
    if ([[URL absoluteString] length] == 0) {
        [[NSAlert alertWithMessageText:@"Invalid URL" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Please provide a valid URL"] runModal];
        return;
    }
    
    NSInteger numberOfRequests = [[self.numberOfRequestsTextField stringValue] integerValue];
    
    for (NSInteger i=0; i<numberOfRequests; i++) {
        AFRequestInfo *requestInfo = [[AFRequestInfo alloc] init];
        requestInfo.requestTimestamp = [NSDate date];
        requestInfo.requestURL = URL;

        [self.requestArrayController addObject:requestInfo];
        
        [cache cacheItemForURL:URL urlCredential:nil completionBlock:^(AFCacheableItem *item) {
            requestInfo.responseData = item.data;
            requestInfo.responseTimestamp = [NSDate dateWithTimeIntervalSinceReferenceDate:item.info.responseTimestamp];
            requestInfo.successful = [NSNumber numberWithBool:YES];
            if (item.IMSRequest) {
                requestInfo.internalRequestType = @"IMS";
            }
            requestInfo.levelIndicatorValue = [NSNumber numberWithBool:1];
            requestInfo.servedFromCache = [NSNumber numberWithBool:item.servedFromCache];
            requestInfo.responseHeader = [item.info.response description];
            [self updateCacheStatusForRequestInfo:requestInfo withItem:item];
        } failBlock:^(AFCacheableItem *item) {
            requestInfo.responseTimestamp = [NSDate dateWithTimeIntervalSinceReferenceDate:item.info.responseTimestamp];
            requestInfo.successful = [NSNumber numberWithBool:NO];
            requestInfo.responseHeader = [item.info.response description];
            requestInfo.levelIndicatorValue = [NSNumber numberWithBool:2];
            [self updateCacheStatusForRequestInfo:requestInfo withItem:item];
        }];
    }
}

- (void)updateCacheStatusForRequestInfo:(AFRequestInfo*)requestInfo withItem:(AFCacheableItem*)item {
    switch (item.cacheStatus) {
        case kCacheStatusDownloading:
            requestInfo.cacheStatus = @"Downloading";
            break;
        case kCacheStatusFresh:
            requestInfo.cacheStatus = @"Fresh";
            break;
        case kCacheStatusModified:
            requestInfo.cacheStatus = @"Modified";
            break;
        case kCacheStatusNew:
            requestInfo.cacheStatus = @"New";
            break;
        case kCacheStatusNotModified:
            requestInfo.cacheStatus = @"NotModified";
            break;
        case kCacheStatusRevalidationPending:
            requestInfo.cacheStatus = @"RevalidationPending";
            break;
        case kCacheStatusStale:
            requestInfo.cacheStatus = @"Stale";
            break;
    }
}

@end
