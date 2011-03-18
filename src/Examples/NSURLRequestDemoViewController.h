//
//  NSURLRequestDemoViewController.h
//  AFCache
//
//  Created by Michael Markowski on 25.08.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface NSURLRequestDemoViewController : UIViewController {
	NSMutableData *receivedData;
	UIImageView *imageView;
}

@property (nonatomic, retain) NSMutableData *receivedData;
@property (nonatomic, retain) IBOutlet UIImageView *imageView;

@end
