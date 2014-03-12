//
//  AFViewController.m
//  demo
//
//  Created by Claus Weymann on 12.03.14.
//  Copyright (c) 2014 purplemotion. All rights reserved.
//

#import "AFViewController.h"

@interface AFViewController ()
@property (strong, nonatomic) IBOutlet UIWebView *demoWebView;

@end

@implementation AFViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
	NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://heise.de"]];
	[self.demoWebView loadRequest:request];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
