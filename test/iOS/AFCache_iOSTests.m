//
//  AFCache_iOSTests.m
//  AFCache-iOSTests
//
//  Created by Michael Markowski on 10.03.11.
//  Copyright 2011 Artifacts - Fine Software Development. All rights reserved.
//

#import "AFCache_iOSTests.h"
#import "AFMediaTypeParser.h"

@implementation AFCache_iOSTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void) testMIMEParsing
{
    AFMediaTypeParser* parser = [[AFMediaTypeParser alloc] initWithMIMEType:@"text/html"];

    STAssertNil([parser textEncoding], @"Text encoding is not nil");
    STAssertEqualObjects(parser.contentType, @"text/html", @"content type is nil");
    [parser release];

    parser = [[AFMediaTypeParser alloc] initWithMIMEType:@"text/html; charset=utf-8"];
    STAssertEqualObjects(parser.textEncoding, @"utf-8", @"text encoding is not utf-8");
    STAssertEqualObjects(parser.contentType, @"text/html", @"content type is not text/html");
    [parser release];

    parser = [[AFMediaTypeParser alloc] initWithMIMEType:@"text/html;bla=foo;charset=utf-8;hello=world"];
    STAssertEqualObjects(parser.textEncoding, @"utf-8", @"text encoding is not utf-8");
    STAssertEqualObjects(parser.contentType, @"text/html", @"content type is not text/html");
    [parser release];
}

@end
