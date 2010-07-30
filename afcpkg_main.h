//
//  afcpkg_main.h
//  AFCache
//
//  Created by Michael Markowski on 22.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AFCachePackager.h"
#import "ZipArchive.h"

@interface afcpkg_main : NSObject {
	NSString *folder;
	NSString *baseURL;
	NSString *maxAge;
	NSTimeInterval lastModifiedOffset;
	AFCachePackager *packager;
}

@property (copy) NSString *folder;
@property (copy) NSString *baseURL;
@property (copy) NSString *maxAge;
@property (assign) NSTimeInterval lastModifiedOffset;
@property (retain) AFCachePackager *packager;

- (void)createPackageWithArgs:(NSUserDefaults*)args;
- (AFCacheableItem*)newCacheableItemForFileAtPath:(NSString*)filepath lastModified:(NSDate*)lastModified;

@end
