//
//  AFMIMEParser.h
//  AFCache-iOS
//
//  Created by Martin Jansen on 25.02.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 * Implements a RFC 2616 confirming parser for extracting the
 * content type and the character encoding from Internet Media
 * Types
 */
@interface AFMediaTypeParser : NSObject {
    NSString* mimeType;
    NSString* __unsafe_unretained _textEncoding;
    NSString* __unsafe_unretained _contentType;
}

@property (unsafe_unretained, nonatomic, readonly) NSString* textEncoding;
@property (unsafe_unretained, nonatomic, readonly) NSString* contentType;

- (id) initWithMIMEType:(NSString*)theMIMEType;

@end
