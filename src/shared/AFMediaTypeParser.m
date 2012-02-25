//
//  AFMIMEParser.m
//  AFCache-iOS
//
//  Created by Martin Jansen on 25.02.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFMIMEParser.h"

@implementation AFMIMEParser

#pragma mark Object lifecycle

- (id) initWithMIMEType:(NSString*)theMIMEType
{
    self = [super init];
    
    if (self) {
        mimeType = [theMIMEType retain];
    }
    
    return self;
}

- (void) dealloc
{
    [mimeType release];

    [super dealloc];
}

#pragma mark -

- (void) parse
{
    
}

- (NSString*) textEncoding
{
    return @"";
}

- (NSString*) contentType
{
    return @"";
}

@end
