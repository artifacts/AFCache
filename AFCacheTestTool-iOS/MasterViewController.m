//
//  MasterViewController.m
//  AFCacheTestTool
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import "MasterViewController.h"
#import "DetailViewController.h"

enum TableRows {
    TableRowShowURLProtocolTest = 0,
    TableRowShowCacheBrowser = 1,
};

enum DisplayModes {
    DisplayModeIcomingResponses = 0,
    DisplayModeCacheBrowser = 1,
};

@implementation MasterViewController

@synthesize detailViewController = _detailViewController;
@synthesize tableView = _tableView;
@synthesize displayMode = _displayMode;
@synthesize incomingResponses = _incomingResponses;
@synthesize path = _path;

- (void)awakeFromNib
{
    //self.clearsSelectionOnViewWillAppear = NO;
    self.contentSizeForViewInPopover = CGSizeMake(320.0, 600.0);
    [super awakeFromNib];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.path = [[AFCache sharedInstance] dataPath];

	// Do any additional setup after loading the view, typically from a nib.
    self.detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];
//    [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO scrollPosition:UITableViewScrollPositionMiddle];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {    
    switch (self.displayMode.selectedSegmentIndex) {
        case DisplayModeCacheBrowser:
        {
            NSError *error = nil;
            NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:&error];
            NSString *filename = [files objectAtIndex:indexPath.row];
            NSString *nextPath = [self.path stringByAppendingPathComponent:filename];
            
            BOOL isDir = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:nextPath isDirectory: &isDir];
            
            if (isDir == YES) {
                MasterViewController *vc = [self.storyboard instantiateViewControllerWithIdentifier:@"MasterViewController"];    
                [vc view];
                [vc setPath:nextPath];
                [vc.displayMode setSelectedSegmentIndex:DisplayModeCacheBrowser];
                [vc.displayMode setHidden:YES];
                [self.navigationController pushViewController:vc animated:YES];
            } else {
                DetailViewController *detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];
                NSString *urlString = [nextPath stringByReplacingOccurrencesOfString:[[AFCache sharedInstance] dataPath] withString:@"http:/"];
                NSURL *url = [NSURL URLWithString:urlString];
                AFCacheableItem *cacheableItem = [[AFCache sharedInstance] cacheableItemFromCacheStore:url];
                if (cacheableItem) {
                    [detailViewController setDetailItem:cacheableItem];
                }
            }
            break;
        }
        case DisplayModeIcomingResponses:
        {
            DetailViewController *detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];
            AFCacheableItem *item = [self.incomingResponses objectAtIndex:indexPath.row];
            [detailViewController setDetailItem:item];            
            break;            
        }
    }
    
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.displayMode.selectedSegmentIndex) {
        case DisplayModeCacheBrowser:
        {
            NSError *error = nil;
            NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:&error];
            return [files count];            
        }
        break;
        case DisplayModeIcomingResponses:
            return [self.incomingResponses count];
            break;            
    }
    return 0;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseIdentifier = @"ResponseCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];    
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    }

    switch (self.displayMode.selectedSegmentIndex) {
        case DisplayModeCacheBrowser:
        {
            NSError *error = nil;
            NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:&error];
            NSString *filename = [files objectAtIndex:indexPath.row];
            cell.textLabel.text = filename;
            break;
        }
        case DisplayModeIcomingResponses:
        {
            AFCacheableItem *item = [self.incomingResponses objectAtIndex:indexPath.row];
            cell.textLabel.text = [item.url lastPathComponent];
            break;            
        }
    }

    return cell;
}

- (void)connectionDidFail:(AFCacheableItem *)cacheableItem {
    
}

- (void)connectionDidFinish:(AFCacheableItem *)cacheableItem {
    [self.incomingResponses addObject:cacheableItem];
    [self.tableView reloadData];
}

- (IBAction)changeDisplayModeAction:(id)sender {
    [self.tableView reloadData];
}

@end
