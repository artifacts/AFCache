//
//  DemoAppDelegate.m
//  Demo
//
//  Created by Michael Markowski on 07.07.10.
//  Copyright Artifacts 2010. All rights reserved.
//

#import "DemoAppDelegate.h"
#import "DemoViewController.h"

@implementation DemoAppDelegate

@synthesize window;
@synthesize viewController;


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {    
    
	// Add NSURLCache to use AFCache in UIWebViews
    AFURLCache* urlCache = [[[AFURLCache alloc] initWithMemoryCapacity:0 diskCapacity:0 diskPath:@""] autorelease];
    [NSURLCache setSharedURLCache:urlCache];	
	
    // Override point for customization after app launch    
    [window addSubview:viewController.view];
    [window makeKeyAndVisible];
	
	return YES;
}


- (void)dealloc {
    [viewController release];
    [window release];
    [super dealloc];
}


@end
