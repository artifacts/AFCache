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

@property (nonatomic, strong) NSURL *packageURL;
@property (nonatomic, strong) NSURL *baseURL;
@property (nonatomic, strong) NSArray *resourceURLs;
@property (nonatomic, strong) NSMutableDictionary *userData;

@end
