//
//  MasterViewController.h
//  AFCacheTestTool
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AFCache.h"

@class DetailViewController;

@interface MasterViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, AFCacheableItemDelegate>

@property (strong, nonatomic) DetailViewController *detailViewController;
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) IBOutlet UISegmentedControl *displayMode;
@property (strong, nonatomic) NSMutableArray *incomingResponses;
@property (nonatomic, retain) NSString *path;

- (IBAction)changeDisplayModeAction:(id)sender;

@end
