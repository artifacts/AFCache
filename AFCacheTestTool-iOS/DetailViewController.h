//
//  DetailViewController.h
//  AFCacheTestTool
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DetailViewController : UIViewController <UISplitViewControllerDelegate, UIWebViewDelegate, UITableViewDelegate, UITableViewDataSource>

@property (strong, nonatomic) id detailItem;

@property (strong, nonatomic) IBOutlet UILabel *detailDescriptionLabel;

@property (strong, nonatomic) IBOutlet UIWebView *webView;

@property (strong, nonatomic) IBOutlet UITableView *tableView;

@property (strong, nonatomic) IBOutlet UILabel *cacheHitLabel;
@property (strong, nonatomic) IBOutlet UILabel *imsLabel;

- (IBAction)reloadAction:(id)sender;
- (IBAction)clearCacheAction:(id)sender;
- (IBAction)setOfflineAction:(id)sender;
- (IBAction)requestCurrentCacheableItem:(id)sender;
- (IBAction)persistCacheAction:(id)sender;

@end
