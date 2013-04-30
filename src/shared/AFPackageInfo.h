//
//  AFPackageItemInfo.h
//  AFCache
//
//  Created by Michael Markowski on 28.01.11.
//  Copyright 2011 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface AFPackageInfo : NSObject {
	NSURL *packageURL;
	NSURL *baseURL;
	NSArray *resourceURLs;
	NSMutableDictionary *userData;
}

@property (nonatomic, retain) NSURL *packageURL;
@property (nonatomic, retain) NSURL *baseURL;
@property (nonatomic, retain) NSArray *resourceURLs;
@property (nonatomic, retain) NSMutableDictionary *userData;

@end
