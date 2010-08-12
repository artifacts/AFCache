/*
 *  testafcache_main.m
 *  AFCache
 *
 *  Created by neonico on 8/12/10.
 *  Copyright 2010 __MyCompanyName__. All rights reserved.
 *
 */


#import <Foundation/Foundation.h>
#import "TestController.h"

int main(int argc, char* argv[])
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    

    TestController* controller = [[TestController alloc] init];
    [controller test];
    
    for (;;)
    {
        [[NSRunLoop currentRunLoop] run];
    }
    
    [pool release];
}