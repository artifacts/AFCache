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

#import "AFCacheTestWithGUI.h"
#import "DateParser.h"
#import "AFCache+PrivateExtensions.h"

@implementation AFCacheTestWithGUI

@synthesize responseTextView;
@synthesize requestHeaderTextView;
@synthesize responseHeaderTextView;
@synthesize fetchButton;
@synthesize activityIndicator;
@synthesize objectsInCacheLabel;
@synthesize internalCacheDataTextView;
@synthesize tickTimer;
@synthesize currentTimeLabel;
@synthesize autoFetch;

- (void)dealloc {
	[autoFetch release];
	[tickTimer release];
	[internalCacheDataTextView release];
	[fetchButton release];
	[activityIndicator release];
	[responseTextView release];
	[requestHeaderTextView release];
	[responseHeaderTextView release];
	[objectsInCacheLabel release];
	[super dealloc];
}

- (void)tick: (NSTimer *) timer {
	currentTimeLabel.text = [NSString stringWithFormat: @"Current time: %@", [[[NSDate date] gh_formatHTTP] description]];
	if (autoFetch.on == YES) [self doFetchAction: nil];
}

- (void)viewWillAppear: (BOOL) animated {
	[self updateStats];
	self.tickTimer = [NSTimer timerWithTimeInterval: 1.0 target: self selector: @selector(tick:) userInfo: nil repeats: YES];
	[[NSRunLoop currentRunLoop] addTimer: tickTimer forMode: NSDefaultRunLoopMode];
}

- (void)viewWillDisappear: (BOOL) animated {
	[tickTimer invalidate];
}

- (IBAction)doFetchAction: (id) sender {
	[activityIndicator startAnimating];
	[[AFCache sharedInstance] cachedObjectForURL: [NSURL URLWithString: kAFCacheTestURL] delegate: self];
	[self updateStats];
}

- (IBAction)doClearCacheAction: (id) sender {
	[[AFCache sharedInstance] invalidateAll];
	[self updateStats];
	internalCacheDataTextView.text = nil;
}

- (void)connectionDidFail: (AFCacheableItem *) cacheableItem {
	[activityIndicator stopAnimating];
	responseTextView.text = [cacheableItem.error description];
	[self updateStats];
}

- (void)connectionDidFinish: (AFCacheableItem *) cacheableItem {
	[activityIndicator stopAnimating];
	responseTextView.text = [cacheableItem asString];

	internalCacheDataTextView.text = [NSString stringWithFormat: @"last-modified: %@\n", [cacheableItem.info.lastModified description]];
	internalCacheDataTextView.text = [internalCacheDataTextView.text stringByAppendingString: [NSString stringWithFormat: @"expireDate: %@\n", [cacheableItem.info.expireDate description]]];
	[self updateStats];
}

- (void)updateStats {
	self.objectsInCacheLabel.text = [NSString stringWithFormat: @"Objects in cache: %d, %d entries in expire table", [[AFCache sharedInstance] numberOfObjectsInDiskCache], [[AFCache sharedInstance].cacheInfoStore count]];
}

@end