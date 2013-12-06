//
//  afcpkg_main.m
//  AFCache
//
//  Created by Michael Markowski on 22.07.10.
//  Copyright 2010 Artifacts - Fine Software Development. All rights reserved.
//

#import "afcpkg_main.h"
#import "AFCache.h"
#import "AFCache+Packaging.h"
#import "AFCacheableItem+Packaging.h"
#import "AFCachePackageCreator.h"

#import <Cocoa/Cocoa.h>

#pragma mark -
#pragma mark main

/* ================================================================================================
 * Main
 * ================================================================================================ */

int main(int argc, char *argv[])
{
    NSUserDefaults *args = [NSUserDefaults standardUserDefaults];
	afcpkg_main *main = [[afcpkg_main alloc] init];
	
	[main createPackageWithArgs:args];
    return 0;
}

@implementation afcpkg_main

//@synthesize folder, baseURL, maxAge, lastModifiedOffset;

#pragma mark -
#pragma mark commandline handling


/* ================================================================================================
 * Create AFCache Package with given commandline args
 * ================================================================================================ */

- (void)createPackageWithArgs:(NSUserDefaults*)args {
    AFCachePackageCreator *packager = [[AFCachePackageCreator alloc] init];
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSError *error = nil;
    
	// folder containing resources
	[options setValue:[args stringForKey:@"folder"] forKey:kPackagerOptionResourcesFolder];
	
	// base url, e.g. http://www.foo.bar (WITHOUT trailing slash)	
	[options setValue:[args stringForKey:@"baseurl"] forKey:kPackagerOptionBaseURL];
	
	// max-age in seconds
	[options setValue:[args stringForKey:@"maxage"] forKey:kPackagerOptionMaxAge];
	
	// Maximum filesize of a cacheable item. Default is unlimited.
	[options setValue:[NSNumber numberWithDouble:[args doubleForKey:@"maxItemFileSize"]] forKey:kPackagerOptionMaxItemFileSize];
	
	// will substract n seconds from file's lastmodfied date
    [options setValue:[NSNumber numberWithDouble:[args doubleForKey:@"lastmodifiedminus"]] forKey:kPackagerOptionLastModifiedMinus];	

	// will add n seconds to file's lastmodfied date
    [options setValue:[NSNumber numberWithDouble:[args doubleForKey:@"lastmodifiedplus"]] forKey:kPackagerOptionLastModifiedPlus];	
    

	// write manifest file in json format (just for testing purposes)
	[options setValue:[args stringForKey:@"json"] forKey:kPackagerOptionOutputFormatJSON];

	// include all files. By default, files starting with a dot are excluded.
	[options setValue:[args stringForKey:@"a"] forKey:kPackagerOptionIncludeAllFiles];

	// output filename
	[options setValue:[args stringForKey:@"outfile"] forKey:kPackagerOptionOutputFilename];

	// Folder containing arbitrary user data (will be accesible via userDataPathForPackageArchiveKey: in AFCache+Packaging.m
	[options setValue:[args stringForKey:@"userdata"] forKey:kPackagerOptionUserDataFolder];

	// Key under which userdata can be accessed. Default is no key.
	[options setValue:[args stringForKey:@"userdatakey"] forKey:kPackagerOptionUserDataKey];
	
	// Create ZIP archive
	BOOL showHelp = ( 0 == [[options valueForKey: kPackagerOptionBaseURL] length] );
	@try {	
		if (showHelp==YES) {
			printf("\n");
			printf("Usage: afcpkg [-outfile] [-maxage] [-baseurl] [-file] [-folder] [-json] [-h] [-a] [-outfile] [-maxItemFileSize] [-userdata]\n");
			printf("\n");
			printf("\t-maxage \t\tmax-age in seconds\n");
			printf("\t-baseurl \t\tbase url, e.g. http://www.foo.bar (WITHOUT trailing slash)\n");
			printf("\t-lastmodifiedplus \tadd n seconds to file's lastmodfied date\n");
			printf("\t-lastmodifiedminus \tsubstract n seconds from file's lastmodfied date\n");
			printf("\t-folder \t\tfolder containing resources\n");
			printf("\t-json \t\t\twrite manifest file in json format (just for testing purposes)\n");
			printf("\t-h \t\t\tdisplay this help output\n");
			printf("\t-a \t\t\tinclude all files. By default, files starting with a dot are excluded.\n");
			printf("\t-outfile \t\t\toutput filename\n");
			printf("\t-maxItemFileSize \t\t\tMaximum filesize of a cacheable item. Default is unlimited.\n");
			printf("\t-userdata \t\t\tFolder containing arbitrary user data (will be accesible via userDataPathForPackageArchiveKey: in AFCache+Packaging.m\n");
			printf("\t-userdatakey \t\t\tKey under which userdata can be accessed. Default is no key (nil).\n");
			printf("\n");
			exit(0);
		} else {
            if (NO == [packager createPackageWithOptions:options error:&error]) {
                [NSException raise:@"Package creation error" format:@"Reason: %@", [error localizedDescription]];
            }
            
		}	
	}
	@catch (NSException * e) {
		NSLog(@"afcpkg error: %@", [e description]);
		printf("Error. See log for details.");
	}
}


@end
