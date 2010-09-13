//
//  CacheableItemDemoController.m
//  AFCache
//
//  Created by Michael Markowski on 31.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "CacheableItemDemoController.h"


@implementation CacheableItemDemoController

@synthesize log, progressView, loadButton, cancelButton, url;

- (IBAction)loadAction:(id)sender {
	progressView.progress = 0.0f;
	loadButton.enabled = NO;
	NSURL *theURL = [NSURL URLWithString:url.text];
	if (theURL) {
		[[AFCache sharedInstance] cachedObjectForURL:theURL delegate:self];
	} else {
		log.text = @"Invalid URL.";
	}
	int pending = [[AFCache sharedInstance].pendingConnections count];
	log.text = [NSString stringWithFormat: @"Started request. Pending connections: %d", pending];	
}

- (IBAction)cancelAction:(id)sender {
	progressView.progress = 0.0f;
	[[AFCache sharedInstance] cancelConnectionsForURL:[NSURL URLWithString:url.text]];
	int pending = [[AFCache sharedInstance].pendingConnections count];
	log.text = [NSString stringWithFormat: @"Canceled request. Pending connections: %d", pending];
	loadButton.enabled = YES;
}

- (IBAction)clearAction:(id)sender {
	[[AFCache sharedInstance] invalidateAll];
	log.text = @"Cleared cache completely.";
}

- (void) connectionDidFail: (AFCacheableItem *) cacheableItem {
	progressView.progress = 0.0f;
	log.text = [NSString stringWithFormat:@"FAIL.\n%@", [cacheableItem.error description]];
}

- (void) connectionDidFinish: (AFCacheableItem *) cacheableItem {
	log.text = [NSString stringWithFormat:@"SUCCESS.\n%@", [cacheableItem description]];
	loadButton.enabled = YES;	
}

- (void) connectionDidReceiveData: (AFCacheableItem *) cacheableItem {
	float totalSize = cacheableItem.contentLength;
	float currentSize = cacheableItem.currentContentLength;
	float percentage = currentSize / (totalSize/100);
	progressView.progress = percentage / 100;
}

- (void)dealloc {
	[log release];
	[url release];
	[progressView release];
	[loadButton release];
	[cancelButton release];	
    [super dealloc];
}


@end
