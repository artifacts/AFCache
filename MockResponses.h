//
//  MockResponses.h
//  AFCache
//
//  Created by Michael Markowski on 26.04.10.
//  Copyright 2010 Artifacts. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MockResponses : NSObject {
}

+ (NSURLResponse *)responseWithURL: (NSURL *) URL expiringInSeconds: (int) seconds;

@end