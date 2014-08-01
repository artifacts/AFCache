//
//  AFAppDelegate.h
//  AFCacheTestTool
//
//  Created by Michael Markowski on 01/08/14.
//  Copyright (c) 2014 artifacts Software GmbH & Co KG. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AFAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSTextField *URLTextField;
@property (strong) IBOutlet NSTextView *responseTextView;
@property (strong) IBOutlet NSButton *requestButton;
@property (strong) IBOutlet NSArrayController *requestArrayController;

@end
