//
//  AFMIMEParser.m
//  AFCache-iOS
//
//  Created by Martin Jansen on 25.02.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFMediaTypeParser.h"

#define kCharsetName @"charset"
#define kTokenDelimiter @";"
#define kParameterDelimiter @"="

@interface AFMediaTypeParser (private)

- (void) parse;
- (NSString*) trim:(NSString*)aString;

@end

@implementation AFMediaTypeParser

@synthesize textEncoding = _textEncoding;
@synthesize contentType = _contentType;

#pragma mark Object lifecycle

- (id) initWithMIMEType:(NSString*)aMIMEType
{
    self = [super init];

    if (self) {
        mimeType = aMIMEType;
        _textEncoding = nil;
        _contentType = nil;

        [self parse];
    }

    return self;
}


#pragma mark -

- (void) parse
{
    NSArray *components = [mimeType componentsSeparatedByString:kTokenDelimiter];

    if (1 >= [components count]) {
        _contentType = [self trim:mimeType];
        return;
    }

    _contentType = [self trim:(NSString*)[components objectAtIndex:0]];
    for (NSUInteger i = 1; i < [components count]; i++) {
        NSString *parameter = [components objectAtIndex:i];
        NSArray *parameterComponents = [parameter componentsSeparatedByString:kParameterDelimiter];

        if (2 != [parameterComponents count]) {
            continue;
        }

        NSString *name = [self trim:[parameterComponents objectAtIndex:0]];
        NSString *value = [self trim:[parameterComponents objectAtIndex:1]];

        if ([name isEqualToString:kCharsetName]) {
            _textEncoding = value;
            break;
        }
    }
}

- (NSString*) trim:(NSString*)aString
{
    // http://stackoverflow.com/a/8293671/132475

    NSMutableString *mStr = [aString mutableCopy];
    CFStringTrimWhitespace((CFMutableStringRef)mStr);

    NSString *result = [mStr copy];

    return result;
}

@end
