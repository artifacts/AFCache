//
//  DemoViewController.h
//  Demo
//
//  Created by Michael Markowski on 07.07.10.
//  Copyright Artifacts 2010. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AFCache.h"

@interface DemoViewController : UIViewController <AFCacheableItemDelegate> {
	UITextView *textView;
	UIWebView *webView;
	UIImageView *imageView;
}

@property (nonatomic, retain) IBOutlet UITextView *textView;
@property (nonatomic, retain) IBOutlet UIWebView *webView;
@property (nonatomic, retain) IBOutlet UIImageView *imageView;

- (void)loadStructure;

@end

