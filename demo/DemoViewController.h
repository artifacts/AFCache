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
}

@property (nonatomic, retain) IBOutlet UITextView *textView;

@end

