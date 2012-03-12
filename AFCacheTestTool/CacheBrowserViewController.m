//
//  CacheBrowserViewController.m
//  AFCacheTestTool
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import "CacheBrowserViewController.h"
#import "AFCache.h"
#import "DetailViewController.h"

@implementation CacheBrowserViewController

@synthesize path = _path;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.path = [[AFCache sharedInstance] dataPath];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
 
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)setPath:(NSString *)aPath {
    _path = aPath;
    [self.tableView reloadData];
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

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:&error];
    return [files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:&error];
    NSString *filename = [files objectAtIndex:indexPath.row];
    cell.textLabel.text = filename;
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{    
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.path error:&error];
    NSString *filename = [files objectAtIndex:indexPath.row];
    NSString *nextPath = [self.path stringByAppendingPathComponent:filename];

    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:nextPath isDirectory: &isDir];

    if (isDir == YES) {
        CacheBrowserViewController *cacheBrowserViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"CacheBrowserViewController"];    
        [cacheBrowserViewController view];
        [cacheBrowserViewController setPath:nextPath];
        [self.navigationController pushViewController:cacheBrowserViewController animated:YES];
    } else {
        DetailViewController *detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];
        NSString *urlString = [nextPath stringByReplacingOccurrencesOfString:[[AFCache sharedInstance] dataPath] withString:@"http:/"];
        NSURL *url = [NSURL URLWithString:urlString];
        AFCacheableItem *cacheableItem = [[AFCache sharedInstance] cacheableItemFromCacheStore:url];
        if (cacheableItem) {
            [detailViewController setDetailItem:cacheableItem];
        }
    }
}

@end
