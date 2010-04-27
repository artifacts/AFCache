/*
 *
 * Copyright 2008 Artifacts - Fine Software Development
 * http://www.artifacts.de
 * Author: Michael Markowski (m.markowski@artifacts.de)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#import <UIKit/UIKit.h>
#import "AFCache.h"
#import "AFCacheableItem.h"

//#define kAFCacheTestURL @"http://localhost/~mic/afcache/afcachetest.php"
#define kAFCacheTestURL @"http://www.systemshutdown.de/afcachetest.php"

@interface AFCacheTestWithGUI : UIViewController <AFCacheableItemDelegate> {
	IBOutlet UITextView *responseTextView;
	IBOutlet UITextView *requestHeaderTextView;
	IBOutlet UITextView *responseHeaderTextView;
	IBOutlet UIButton *fetchButton;
	IBOutlet UIActivityIndicatorView *activityIndicator;
	IBOutlet UILabel *objectsInCacheLabel;
	IBOutlet UITextView *internalCacheDataTextView;
	IBOutlet UILabel *currentTimeLabel;
	IBOutlet UISwitch *autoFetch;
	NSTimer *tickTimer;
}

@property (nonatomic, retain) UITextView *responseTextView;
@property (nonatomic, retain) UITextView *requestHeaderTextView;
@property (nonatomic, retain) UITextView *responseHeaderTextView;
@property (nonatomic, retain) UIButton *fetchButton;
@property (nonatomic, retain) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, retain) UILabel *objectsInCacheLabel;
@property (nonatomic, retain) UITextView *internalCacheDataTextView;
@property (nonatomic, retain) NSTimer *tickTimer;
@property (nonatomic, retain) UILabel *currentTimeLabel;
@property (nonatomic, retain) UISwitch *autoFetch;

- (IBAction)doFetchAction: (id) sender;
- (IBAction)doClearCacheAction: (id) sender;

- (void)updateStats;

@end