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

@synthesize textView;

- (void)viewDidAppear:(BOOL)animated {
	textView.text = kDemoURL;
	[[AFCache sharedInstance] cachedObjectForURL:[NSURL URLWithString:kDemoURL] delegate:self options:0];
}

- (void)connectionDidFail:(AFCacheableItem *)cacheableItem {
	textView.text = [cacheableItem.error description];
}

- (void)connectionDidFinish:(AFCacheableItem *)cacheableItem {
	textView.text = [cacheableItem description];	
}

- (void)dealloc {
	[textView release];
    [super dealloc];
}

@end
