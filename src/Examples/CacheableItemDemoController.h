//
//  CacheableItemDemoController.h
//  AFCache
//
//  Created by Michael Markowski on 31.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AFCache.h"
#import "AFCacheableItem.h"

@interface CacheableItemDemoController : UIViewController {
	UITextView *log;
	UITextView *url;
	UIProgressView *progressView;
	UIButton *loadButton;
	UIButton *cancelButton;
	UIToolbar *toolbar;
}

@property (nonatomic, retain) IBOutlet UITextView *log;
@property (nonatomic, retain) IBOutlet UITextView *url;
@property (nonatomic, retain) IBOutlet UIProgressView *progressView;
@property (nonatomic, retain) IBOutlet UIButton *loadButton;
@property (nonatomic, retain) IBOutlet UIButton *cancelButton;
@property (nonatomic, retain) IBOutlet UIToolbar *toolbar;

- (IBAction)loadAction:(id)sender;
- (IBAction)cancelAction:(id)sender;
- (IBAction)clearAction:(id)sender;
- (IBAction)dismissKeyboardAction:(id)sender;

@end
