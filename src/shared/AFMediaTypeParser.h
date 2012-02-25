//
//  AFMIMEParser.h
//  AFCache-iOS
//
//  Created by Martin Jansen on 25.02.12.
//  Copyright (c) 2012 Artifacts - Fine Software Development. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFMIMEParser : NSObject {
    NSString *mimeType;
}

- (id) initWithMIMEType:(NSString*)theMIMEType;

- (NSString*) textEncoding;
- (NSString*) contentType;

@end
