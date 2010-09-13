//
//  AFNSDate+Parsing.h copied from GHNSDate+Parsing.h by Gabriel Handford
//  Original copyright notice below.
//

//
//  Created by Gabe on 3/18/08.
//  Copyright 2008 Gabriel Handford
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

#import "DateParser.h"


@implementation DateParser


+ (NSDate *)gh_parseISO8601: (NSString *) dateString {
	if (!dateString) return nil;
	return [[self gh_iso8601DateFormatter] dateFromString: dateString];
}

+ (NSDate *)gh_parseRFC822: (NSString *) dateString {
	if (!dateString) return nil;
	return [[self gh_rfc822DateFormatter] dateFromString: dateString];
}

+ (NSDate *)gh_parseHTTP: (NSString *) dateString {
	if (!dateString) return nil;
	NSDate *parsed = nil;
	parsed = [[self gh_rfc1123DateFormatter] dateFromString: dateString];
	if (parsed) return parsed;
	parsed = [[self gh_rfc850DateFormatter] dateFromString: dateString];
	if (parsed) return parsed;
	parsed = [[self gh_ascTimeDateFormatter] dateFromString: dateString];
	return parsed;
}

+ (NSDate *)gh_parseTimeSinceEpoch: (id) timeSinceEpoch {
	return [self gh_parseTimeSinceEpoch: timeSinceEpoch withDefault: timeSinceEpoch];
}

+ (NSDate *)gh_parseTimeSinceEpoch: (id) timeSinceEpoch withDefault: (id) value {
	if (!timeSinceEpoch) return value;
	return [NSDate dateWithTimeIntervalSince1970: [timeSinceEpoch longLongValue]];
}

- (NSString *)gh_formatRFC822 {
	return [[[self class] gh_rfc822DateFormatter] stringFromDate: self];
}

- (NSString *)gh_formatHTTP {
	return [[[self class] gh_rfc1123DateFormatter] stringFromDate: self];
}

+ (NSString *)formatHTTPDate: (NSDate *) date {
	return [[[self class] gh_rfc1123DateFormatter] stringFromDate: date];
}

- (NSString *)gh_formatISO8601 {
	return [[[self class] gh_iso8601DateFormatter] stringFromDate: self];
}

+ (NSDateFormatter *)gh_rfc822DateFormatter {
	NSDateFormatter *gh_rfc822DateFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[gh_rfc822DateFormatter setFormatterBehavior: NSDateFormatterBehavior10_4];
	// Need to force US locale when generating otherwise it might not be 822 compatible
	[gh_rfc822DateFormatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US"] autorelease]];
	[gh_rfc822DateFormatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
	[gh_rfc822DateFormatter setDateFormat: @"EEE, dd MMM yyyy HH:mm:ss ZZZ"];
	return gh_rfc822DateFormatter;
}

+ (NSDateFormatter *)gh_iso8601DateFormatter {
	// Example: 2007-10-18T16:05:10.000Z
	NSDateFormatter *gh_is8601DateFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[gh_is8601DateFormatter setFormatterBehavior: NSDateFormatterBehavior10_4];
	// Need to force US locale when generating otherwise it might not be 8601 compatible
	[gh_is8601DateFormatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US"] autorelease]];
	[gh_is8601DateFormatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
	[gh_is8601DateFormatter setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
	return gh_is8601DateFormatter;
}

+ (NSDateFormatter *)gh_rfc1123DateFormatter {
	// Example: "Wed, 01 Mar 2006 12:00:00 GMT"
	NSDateFormatter *gh_rfc1123DateFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[gh_rfc1123DateFormatter setFormatterBehavior: NSDateFormatterBehavior10_4];
	// Need to force US locale when generating otherwise it might not be 822 compatible
	[gh_rfc1123DateFormatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US"] autorelease]];
	[gh_rfc1123DateFormatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
	[gh_rfc1123DateFormatter setDateFormat: @"EEE, dd MMM yyyy HH:mm:ss zzz"];
	return gh_rfc1123DateFormatter;
}

+ (NSDateFormatter *)gh_rfc850DateFormatter {
	// Example: Sunday, 06-Nov-94 08:49:37 GMT
	NSDateFormatter *gh_rfc850DateFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[gh_rfc850DateFormatter setFormatterBehavior: NSDateFormatterBehavior10_4];
	[gh_rfc850DateFormatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US"] autorelease]];
	[gh_rfc850DateFormatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
	[gh_rfc850DateFormatter setDateFormat: @"EEEE, dd-MMM-yy HH:mm:ss zzz"];
	return gh_rfc850DateFormatter;
}

+ (NSDateFormatter *)gh_ascTimeDateFormatter {
	// Example: Sun Nov  6 08:49:37 1994
	NSDateFormatter *gh_ascTimeDateFormatter = [[[NSDateFormatter alloc] init] autorelease];
	[gh_ascTimeDateFormatter setFormatterBehavior: NSDateFormatterBehavior10_4];
	[gh_ascTimeDateFormatter setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US"] autorelease]];
	[gh_ascTimeDateFormatter setTimeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
	[gh_ascTimeDateFormatter setDateFormat: @"EEE MMM d HH:mm:ss yyyy"];
	return gh_ascTimeDateFormatter;
}

@end