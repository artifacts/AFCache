//
//  DemoViewController.m
//  Demo
//
//  Created by Michael Markowski on 07.07.10.
//  Copyright Artifacts 2010. All rights reserved.
//

#import "DemoViewController.h"

//#define kDemoURL @"http://www.google.com/intl/en_ALL/images/logos/images_logo_lg.gif"
#define kDemoURL @"http://upload.wikimedia.org/wikipedia/commons/6/63/Wikipedia-logo.png"
#define kWebDemoURL @"http://www.wikipedia.org"
//#define kPackageDemoURL @"http://localhost/~mic/afcache/afcachepackage.zip"
#define kPackageDemoURL @"http://www.artifacts.de/afcache/demopackage.zip"

@implementation DemoViewController

@synthesize textView, webView, imageView;

- (void)viewDidAppear:(BOOL)animated {
	// load an image ansychronously
	textView.text = kDemoURL;
	[[AFCache sharedInstance] requestPackageArchive:[NSURL URLWithString:kPackageDemoURL] delegate:self];	
}

- (void)connectionDidFail:(AFCacheableItem *)cacheableItem {
	textView.text = [cacheableItem.error description];
	NSLog(@"cache request did fail for URL: %@", [cacheableItem.url absoluteString]);	
}

- (void)connectionDidFinish:(AFCacheableItem *)cacheableItem {
	textView.text = [cacheableItem description];
	UIImage *img = [UIImage imageWithData:cacheableItem.data];
	self.imageView.image = img;
	NSLog(@"cache loaded resource for URL: %@", [cacheableItem.url absoluteString]);
}

- (void) packageArchiveDidReceiveData: (AFCacheableItem *) cacheableItem {
	float totalSize = cacheableItem.contentLength;
	float currentSize = [cacheableItem.data length];
	float percentage = currentSize / (totalSize/100);
//	[self.progressView setProgress:currentSize / totalSize];
	if (percentage < 100) {
		NSLog(@"%.0f%% loaded", percentage);
	}	
}

- (void) packageArchiveDidFinishLoading: (AFCacheableItem *) cacheableItem {
	NSLog(@"Loaded package. Extracting...");
	[[AFCache sharedInstance] consumePackageArchive:cacheableItem];
}

- (void) packageArchiveDidFinishExtracting: (AFCacheableItem *) cacheableItem {
	NSLog(@"Extracted package.");
	[[AFCache sharedInstance] setOffline:YES];
	NSLog(@"Setting cache into offline mode.");
	[self loadContent];
}

- (void) packageArchiveDidFailLoading: (AFCacheableItem *) cacheableItem {
	NSLog(@"FAILED loading package. No network connection?");
	[self loadContent];
}

- (void)loadContent {
	[[AFCache sharedInstance] cachedObjectForURL:[NSURL URLWithString:kDemoURL] delegate:self options:0];
	// load request in webview, to demonstrate that webview is asking the cache for every url.
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:kWebDemoURL]];
	[webView loadRequest:request];	
}

- (void)dealloc {
	[imageView release];
	[textView release];
	[webView release];
    [super dealloc];
}

@end
