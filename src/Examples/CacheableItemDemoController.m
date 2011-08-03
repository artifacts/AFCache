//
//  CacheableItemDemoController.m
//  AFCache
//
//  Created by Michael Markowski on 31.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "CacheableItemDemoController.h"


@implementation CacheableItemDemoController

@synthesize log, progressView, loadButton, cancelButton, url, toolbar;

- (void)viewDidLoad {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidHide:) name:UIKeyboardDidHideNotification object:nil];
	toolbar.alpha = 0;
}

- (void)viewDidUnload {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillShow:(NSNotification*)notif {
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.25];
	toolbar.alpha = 1;
	[UIView commitAnimations];	
}

- (void)keyboardDidHide:(NSNotification*)notif {
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:0.25];
	toolbar.alpha = 0;
	[UIView commitAnimations];	
}

- (IBAction)loadAction:(id)sender {
	progressView.progress = 0.0f;
	loadButton.enabled = NO;
	int pending = [[AFCache sharedInstance].pendingConnections count];
	log.text = [NSString stringWithFormat: @"Started request. Pending connections: %d", pending+1];	
	NSURL *theURL = [NSURL URLWithString:url.text];
	if (theURL) {
		[[AFCache sharedInstance] cachedObjectForURL:theURL delegate:self];
	} else {
		log.text = @"Invalid URL.";
	}
}
- (IBAction)dismissKeyboardAction:(id)sender {
	[url resignFirstResponder];
}

- (IBAction)cancelAction:(id)sender {
	progressView.progress = 0.0f;
	[[AFCache sharedInstance] cancelAsynchronousOperationsForDelegate:self];
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

- (void) cacheableItemDidReceiveData: (AFCacheableItem *) cacheableItem {
	float totalSize = cacheableItem.info.contentLength;
	float currentSize = cacheableItem.currentContentLength;
	float percentage = currentSize / (totalSize/100);
	progressView.progress = percentage / 100;
}

- (void)dealloc {
	[toolbar release];
	[log release];
	[url release];
	[progressView release];
	[loadButton release];
	[cancelButton release];	
    [super dealloc];
}


@end
