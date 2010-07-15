//
//  DemoViewController.m
//  Demo
//
//  Created by Michael Markowski on 07.07.10.
//  Copyright Artifacts 2010. All rights reserved.
//

#import "DemoViewController.h"

#define kDemoURL @"http://www.google.com/intl/en_ALL/images/logos/images_logo_lg.gif"

@implementation DemoViewController

@synthesize textView, webView;

- (void)viewDidAppear:(BOOL)animated {
	// load an image ansychronously
	textView.text = kDemoURL;
	[[AFCache sharedInstance] cachedObjectForURL:[NSURL URLWithString:kDemoURL] delegate:self options:0];
	
	// load request in webview, to demonstrate that webview is asking the cache for every url.
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://www.google.de"]];
	[webView loadRequest:request];
}

- (void)connectionDidFail:(AFCacheableItem *)cacheableItem {
	textView.text = [cacheableItem.error description];
	NSLog(@"cache request did fail for URL: %@", [cacheableItem.url absoluteString]);	
}

- (void)connectionDidFinish:(AFCacheableItem *)cacheableItem {
	textView.text = [cacheableItem description];
	NSLog(@"cache loaded resource for URL: %@", [cacheableItem.url absoluteString]);
}

- (void)dealloc {
	[textView release];
	[webView release];
    [super dealloc];
}

@end
