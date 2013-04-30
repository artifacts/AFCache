//
//  AFCachePackageCreator.h
//  AFCache
//
//  Created by Michael Markowski on 22.03.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFCache.h"
#import "AFCacheableItem.h"
#import "AFCache+Packaging.h"
#import "AFCacheableItem+Packaging.h"

#define kPackagerOptionResourcesFolder @"folder"
#define kPackagerOptionBaseURL @"baseurl"
#define kPackagerOptionMaxAge @"maxage"
#define kPackagerOptionMaxItemFileSize @"maxItemFileSize"
#define kPackagerOptionLastModifiedMinus @"lastmodifiedminus"
#define kPackagerOptionLastModifiedPlus @"lastmodifiedplus"
#define kPackagerOptionOutputFormatJSON @"json"
#define kPackagerOptionOutputFilename @"outfile"
#define kPackagerOptionIncludeAllFiles @"a"
#define kPackagerOptionUserDataFolder @"userdata"
#define kPackagerOptionUserDataKey @"userdatakey"
#define kPackagerOptionFileToURLMap @"FileToURLMap"

@interface AFCachePackageCreator : NSObject

- (AFCacheableItem*)newCacheableItemForFileAtPath:(NSString*)filepath lastModified:(NSDate*)lastModified baseURL:(NSString*)baseURL maxAge:(NSNumber*)maxAge baseFolder:(NSString*)folder;
- (BOOL)createPackageWithOptions:(NSDictionary*)options error:(NSError**)inError;

@end
