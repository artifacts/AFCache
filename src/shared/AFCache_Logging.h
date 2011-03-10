/*
 *  AFCache_Logging.h
 *  AFCache
 *
 *  Created by Michael Markowski on 08.02.11.
 *  Copyright 2011 Artifacts - Fine Software Development. All rights reserved.
 *
 */

#ifdef AFCACHE_LOGGING_ENABLED

#define AFLog(fmt, ...) NSLog((fmt), ## __VA_ARGS__)

#else

#define AFLog(fmt, ...) /* */

#endif

#ifdef USE_ENGINEROOM
// to use EngineRoom, include EngineRoom-OSX.xcodeproj in the 

// if we use EngineRoom we should log all the time
#undef AFCACHE_LOGGING_ENABLED
#define AFCACHE_LOGGING_ENABLED true

#import <EngineRoom/logpoints_default.h>

// define an NSLog compatible macro which creates logpoints with keyword AFCache
#define AFCacheLPLog(fmt, ...) ( (void) lplog_c_printf_v1( LOGPOINT_FLAGS_DEBUG | LOGPOINT_NSSTRING, "NSLog", "AFCache", kLogPointLabelNone, kLogPointFormatInfoNone, fmt, ## __VA_ARGS__ ) )

#define NSLog AFCacheLPLog

#else

#define AFCacheLPLog AFLog

#endif
