//
//  LogicTests.h
//  AFCache
//
//  Created by Michael Markowski on 21.04.10.
//  Copyright 2010 Artifacts. All rights reserved.
//
//  See Also: http://developer.apple.com/iphone/library/documentation/Xcode/Conceptual/iphone_development/135-Unit_Testing_Applications/unit_testing_applications.html

//  Application unit tests contain unit test code that must be injected into an application to run correctly.
//  Define USE_APPLICATION_UNIT_TEST to 0 if the unit test code is designed to be linked into an independent test executable.

#import <SenTestingKit/SenTestingKit.h>
#import "AFCache.h"

@interface LogicTests : SenTestCase <AFCacheableItemDelegate> {
	BOOL asyncRequestFinished;
	NSAutoreleasePool *pool;
	AFCacheableItem *item;
}

@property (nonatomic, retain) AFCacheableItem *item;

@end