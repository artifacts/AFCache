/*
 * AFRegexString
 * Adds regular expressions to NSString
 *
 * Copyright 2008 Artifacts - Fine Software Development
 * http://www.artifacts.de
 * Author: Michael Markowski (m.markowski@artifacts.de)
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Borrowed rreplace function from: http://www.daniweb.com/code/snippet733.html
 * TkTkorrovi
 *
 * Influenced by CSRegex http://www.cocoadev.com/index.pl?CSRegex 
 * by Dag Ågren aka WAHa
 * 
 */

#import "AFRegexString.h"
#import "regex.h"

/*
 * Replaces all occurences and stores it in buf
 */
int rreplace (char *buf, int size, regex_t *re, char *rp)
{
    char *pos;
    long long sub, so, n;
    regmatch_t pmatch [10]; /* regoff_t is int so size is int */
	
    if (regexec (re, buf, 10, pmatch, 0)) return 0;
    for (pos = rp; *pos; pos++) 
	{
        if (*pos == '\\' && *(pos + 1) > '0' && *(pos + 1) <= '9') 
		{
            so = pmatch [*(pos + 1) - 48].rm_so;
            n = pmatch [*(pos + 1) - 48].rm_eo - so;
            if (so < 0 || strlen (rp) + n - 1 > size) return 1;
            memmove (pos + n, pos + 2, strlen (pos) - 1);
            memmove (pos, buf + so, n);
            pos = pos + n - 2;
        }
	}
    sub = pmatch [1].rm_so; /* no repeated replace when sub >= 0 */
    for (pos = buf; !regexec (re, pos, 1, pmatch, 0); ) 
	{
        n = pmatch [0].rm_eo - pmatch [0].rm_so;
        pos += pmatch [0].rm_so;
        if (strlen (buf) - n + strlen (rp) + 1 > size) return 1;
        memmove (pos + strlen (rp), pos + n, strlen (pos) - n + 1);
        memmove (pos, rp, strlen (rp));
        pos += strlen (rp);
        if (sub >= 0) break;
    }
    return 0;
}

@implementation NSString (AFRegex)

- (NSString *)stringByRegex:(NSString*)pattern substitution:(NSString*)substitute
{
	regex_t preg;
	NSString *result = nil;
	
	// compile pattern
	int err = regcomp(&preg, [pattern UTF8String], 0 | REG_ICASE | REG_EXTENDED);
	if (err)
	{
		char errmsg[256];
		regerror(err, &preg, errmsg, sizeof(errmsg));		
//		[NSException raise:@"AFRegexStringException"
//					format:@"Regex compilation failed for \"%@\": %s", pattern, errmsg];
		return [NSString stringWithString:self];
	}
	else
	{
		char buffer[4096];
		char *buf = buffer;
		const char *utf8String = [self UTF8String];

		if(strlen(utf8String) >= sizeof(buffer))
		    buf = malloc(strlen(utf8String) + 1);

		strcpy(buf, utf8String);
		char *replaceStr = (char*)[substitute UTF8String];
		
		if (rreplace (buf, 4096, &preg, replaceStr))
		{
//			[NSException raise:@"AFRegexStringException"
//						format:@"Replace failed"];
			result = [NSString stringWithString:self];
		}
		else
		{
			result = [NSString stringWithUTF8String:buf];
		}	

		if(buf != buffer)
		    free(buf);
	}
	
	
	regfree(&preg);  // fixme: used to be commented
	return result;
}

- (BOOL)matchesPattern:(NSString*)pattern
{
	//TODO
	return NO;
}

/*
 OPTIONS:
 
 REG_EXTENDED  Compile modern (``extended'') REs, rather than the obsolete (``basic'') REs that are the default.
 REG_BASIC     This is a synonym for 0, provided as a counterpart to REG_EXTENDED to improve readability.
 REG_NOSPEC    Compile with recognition of all special characters turned off.  All characters are thus considered ordinary, so the
 ``RE'' is a literal string.  This is an extension, compatible with but not specified by IEEE Std 1003.2 (``POSIX.2''),
 and should be used with caution in software intended to be portable to other systems.  REG_EXTENDED and REG_NOSPEC may
 not be used in the same call to regcomp().
 
 REG_ICASE     Compile for matching that ignores upper/lower case distinctions.  See re_format(7).
 REG_NOSUB     Compile for matching that need only report success or failure, not what was matched.
 REG_NEWLINE   Compile for newline-sensitive matching.  By default, newline is a completely ordinary character with no special meaning
 in either REs or strings.  With this flag, `[^' bracket expressions and `.' never match newline, a `^' anchor matches
 the null string after any newline in the string in addition to its normal function, and the `$' anchor matches the null
 string before any newline in the string in addition to its normal function.
 
 REG_PEND      The regular expression ends, not at the first NUL, but just before the character pointed to by the re_endp member of
 the structure pointed to by preg.  The re_endp member is of type const char *.  This flag permits inclusion of NULs in
 the RE; they are considered ordinary characters.  This is an extension, compatible with but not specified by IEEE Std
 1003.2 (``POSIX.2''), and should be used with caution in software intended to be portable to other systems.
 */
- (BOOL)matchesPattern:(NSString*)pattern options:(int)options
{
	//TODO
	return NO;	
}

-(NSString *)escapedPattern
{
	unsigned long len = [self length];
	NSMutableString *escaped=[NSMutableString stringWithCapacity:len];
	
	for(int i=0; i<len; i++)
	{
		unichar c=[self characterAtIndex:i];
		if (c=='^' || 
			c=='.' || 
			c=='[' || 
			c=='$' ||
			c=='(' || 
			c==')' ||
			c=='|' ||
			c=='*' || 
			c=='+' ||
			c=='?' ||
			c=='{' ||
			c=='\\') [escaped appendFormat:@"\\%C", c];
		else [escaped appendFormat:@"%C", c];
	}
	return [NSString stringWithString:escaped];
}

@end
