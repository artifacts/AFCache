//
//  DetailViewController.m
//  AFCacheTestTool
//
//  Created by Michael Markowski on 11.03.12.
//  Copyright (c) 2012 artifacts Software GmbH & Co. KG. All rights reserved.
//

#import "DetailViewController.h"
#import "AFCache.h"
#import "AFCacheableItemCell.h"
#import "AppDelegate.h"

enum TableSections {
    TableSectionCacheableItem = 0,
    TableSectionCacheableItemInfo = 1,
    TableSectionRequest = 2,
    TableSectionResponse = 3,
};

enum TableRowsCacheableItem {
    TableRowUrl,
    TableRowPersistable,
    TableRowIgnoreErrors,
    TableRowError,
    TableRowValidUntil,
    TableRowCacheStatus,
    TableRowUserData,
    TableRowIsPackageArchive,
    TableRowCurrentContentLength,
    TableRowUsername,
    TableRowPassword,
    TableRowIsRevalidating,
    TableRowIMSRequest,
}; NSUInteger TableRowsCacheableItemNumberOfRows = 13;

enum TableRowsCacheableItemInfo {
    InfoRequestTimestamp,
    InfoResponseTimestamp,
    InfoServerDate,
    InfoLastModified, 
    InfoAge, 
    InfoMaxAge, 
    InfoExpireDate, 
    InfoETag, 
    InfoStatusCode, 
    InfoContentLength, 
    InfoMimeType, 
    InfoResponseURL, 
    InfoRequest, 
    InfoResponse
}; NSUInteger TableRowsCacheableItemInfoNumberOfRows = 14;

NSUInteger TableRowsRequestNumberOfRows = 1;
NSUInteger TableRowsResponseNumberOfRows = 1;

@interface DetailViewController ()
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
- (void)configureView;
@end

@implementation DetailViewController

@synthesize detailItem = _detailItem;
@synthesize detailDescriptionLabel = _detailDescriptionLabel;
@synthesize masterPopoverController = _masterPopoverController;
@synthesize webView = _webView;
@synthesize tableView = _tableView;
@synthesize cacheHitLabel = _cacheHitLabel;
@synthesize imsLabel = _imsLabel;

#pragma mark - Actions

- (IBAction)reloadAction:(id)sender {
    [((AppDelegate*)[UIApplication sharedApplication].delegate) reinitIncomingResponses];
    
    NSURL *url = [NSURL URLWithString:@"http://www.artifacts.de/index_en.html"];
    //NSURL *url = [NSURL URLWithString:@"http://localhost/~mic/artifacts/index.html"];
    //NSURL *url = [NSURL URLWithString:@"http://localhost/~mic/artifacts/img/images/portfolio/portrait-michael-markowski.jpg"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [_webView loadRequest:request];
}

#pragma mark - WebView delegate methods

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self configureView];
}

#pragma mark - Managing the detail item

- (void)setDetailItem:(id)newDetailItem
{
    if (_detailItem != newDetailItem) {
        _detailItem = newDetailItem;
        
        // Update the view.
        [self configureView];
    }

    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }        
}

- (void)configureView
{    
    // Update the user interface for the detail item.
    if (![_detailItem isKindOfClass:[AFCacheableItem class]]) return;
    AFCacheableItem *item = _detailItem;
    
    if (self.detailItem) {        
        self.imsLabel.text = (item.IMSRequest != nil)?@"YES":@"NO";
        self.cacheHitLabel.text = (item.servedFromCache==YES)?@"YES":@"NO";
        [self.tableView reloadData];
    }
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
	// Do any additional setup after loading the view, typically from a nib.
    [self configureView];
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

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    barButtonItem.title = NSLocalizedString(@"Master", @"Master");
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case TableSectionCacheableItem:
            return TableRowsCacheableItemNumberOfRows;
            break;
        case TableSectionCacheableItemInfo:
            return TableRowsCacheableItemInfoNumberOfRows;
            break;
        case TableSectionRequest:
            return TableRowsRequestNumberOfRows;
            break;
        case TableSectionResponse:
            return TableRowsResponseNumberOfRows;
            break;            
    }
    return 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseIdentifier = @"AFCacheableItemCell";
    AFCacheableItemCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    AFCacheableItem *cacheableItem = self.detailItem;

    if (cell == nil) {
        cell = [[AFCacheableItemCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    }
    
    cell.keyLabel.text = @"";
    cell.valueLabel.text = @"";

    switch (indexPath.section) {
        case TableSectionCacheableItem:
            switch (indexPath.row) {
                case TableRowUrl:
                    cell.keyLabel.text = @"URL";
                    cell.valueLabel.text = [cacheableItem.url absoluteString];                     
                    break;                    
                case TableRowPersistable:                    
                    cell.keyLabel.text = @"Persistable";
                    cell.valueLabel.text = cacheableItem.persistable?@"YES":@"NO";
                    break;                    
                case TableRowIgnoreErrors:                    
                    cell.keyLabel.text = @"IgnoreErrors";
                    cell.valueLabel.text = cacheableItem.ignoreErrors?@"YES":@"NO";
                    break;                    
                case TableRowError:                    
                    cell.keyLabel.text = @"Error";
                    cell.valueLabel.text = [cacheableItem.error description];
                    break;                    
                case TableRowValidUntil:                    
                    cell.keyLabel.text = @"ValidUntil";
                    cell.valueLabel.text = [cacheableItem.validUntil description];
                    break;                    
                case TableRowCacheStatus:                    
                    cell.keyLabel.text = @"Cache Status";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%d", cacheableItem.cacheStatus];
                    break;                    
                case TableRowUserData:                    
                    cell.keyLabel.text = @"UserData";
                    cell.valueLabel.text = cacheableItem.userData;
                    break;                    
                case TableRowIsPackageArchive:                    
                    cell.keyLabel.text = @"Is Package Archive";
                    cell.valueLabel.text = cacheableItem.isPackageArchive?@"YES":@"NO";
                    break;                    
                case TableRowCurrentContentLength:                    
                    cell.keyLabel.text = @"CurentContentLength";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%d", cacheableItem.currentContentLength];
                    break;                    
                case TableRowUsername:                    
                    cell.keyLabel.text = @"Username";
                    cell.valueLabel.text = cacheableItem.username;
                    break;                    
                case TableRowPassword:                    
                    cell.keyLabel.text = @"Password";
                    cell.valueLabel.text = cacheableItem.password;
                    break;                    
                case TableRowIsRevalidating:                    
                    cell.keyLabel.text = @"Is Revalidating";
                    cell.valueLabel.text = cacheableItem.isRevalidating?@"YES":@"NO";
                    break;                                       
                case TableRowIMSRequest:
                    cell.keyLabel.text = @"If-Modified-Since Request";
                    cell.valueLabel.text = [cacheableItem.IMSRequest description];
                    break;                                                           
            }
            break;
        case TableSectionCacheableItemInfo:
            switch (indexPath.row) {
                case InfoRequestTimestamp:
                    cell.keyLabel.text = @"Request Timestamp";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%f", cacheableItem.info.requestTimestamp];
                    break;                    
                case InfoResponseTimestamp:                    
                    cell.keyLabel.text = @"Response Timestamp";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%f", cacheableItem.info.responseTimestamp];
                    break;                    
                case InfoServerDate:                    
                    cell.keyLabel.text = @"Server Date";
                    cell.valueLabel.text = [cacheableItem.info.serverDate description];
                    break;                    
                case InfoLastModified:                    
                    cell.keyLabel.text = @"Last Modified";
                    cell.valueLabel.text = [cacheableItem.info.lastModified description];
                    break;                    
                case InfoAge:                    
                    cell.keyLabel.text = @"Age";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%d", cacheableItem.info.age];
                    break;                    
                case InfoMaxAge:                    
                    cell.keyLabel.text = @"Max Age";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%d", cacheableItem.info.maxAge];
                    break;                    
                case InfoExpireDate:                    
                    cell.keyLabel.text = @"Expire Date";
                    cell.valueLabel.text = [cacheableItem.info.expireDate description];
                    break;                    
                case InfoETag:                    
                    cell.keyLabel.text = @"ETag";
                    cell.valueLabel.text = cacheableItem.info.eTag;
                    break;                    
                case InfoStatusCode:                    
                    cell.keyLabel.text = @"Status Code";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%d", cacheableItem.info.statusCode];
                    break;                    
                case InfoContentLength:                    
                    cell.keyLabel.text = @"Content Length";
                    cell.valueLabel.text = [NSString stringWithFormat:@"%d", cacheableItem.info.contentLength];
                    break;                    
                case InfoMimeType:                    
                    cell.keyLabel.text = @"MimeType";
                    cell.valueLabel.text = cacheableItem.info.mimeType;
                    break;                    
                case InfoResponseURL:                    
                    cell.keyLabel.text = @"ResponseURL";
                    cell.valueLabel.text = [cacheableItem.info.responseURL absoluteString];
                    break;                                       
            }
            break;
        case TableSectionRequest:
            cell.keyLabel.text = @"Request";
            cell.valueLabel.text = [cacheableItem.info.request description];
            break;
        case TableSectionResponse:
            cell.keyLabel.text = @"Response";
            cell.valueLabel.text = [cacheableItem.info.response description];
            break;
    }
    return cell;
}



- (NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case TableSectionCacheableItem:
            return @"Cachable Item";
            break;
        case TableSectionCacheableItemInfo:
            return @"Cachable Item Info";
            break;
        case TableSectionRequest:
            return @"Request";
            break;
        case TableSectionResponse:
            return @"Response";
            break;
    }
    return nil;
}

- (IBAction)persistCacheAction:(id)sender {
    [[AFCache sharedInstance] archive];
}

- (IBAction)clearCacheAction:(id)sender {
    [[AFCache sharedInstance] invalidateAll];
}

- (IBAction)setOfflineAction:(id)sender {
    UISwitch *theSwitch = sender;
    BOOL offline = theSwitch.on;
    [[AFCache sharedInstance] setOffline:offline];
}

- (IBAction)requestCurrentCacheableItem:(id)sender {
    AFCacheableItem *cacheableItem = self.detailItem;
    [self.webView loadRequest:[NSURLRequest requestWithURL: cacheableItem.url]];
}

@end
