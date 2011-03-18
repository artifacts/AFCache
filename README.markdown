## IMPORTANT NOTICE FOR UPGRADING FROM OLDER VERSIONS 
### (before 2011/02/08) TO 0.7 (after 2011/02/08)

Unfortunately, "converting" the branch "bip" to master the way I did it, might
have not been the best solution.
You will get conflicts when you just do a "git pull" on the (old) master branch. 
The easiest solution might be to drop the old master and clone it again. 
Sorry for that!


## What is AFCache?

AFCache is an HTTP disk cache for use on iPhone/iPad and OSX.
It can be linked as a static library or as a framework.
The cache was initially written because on iOS, NSURLCache ignores NSURLCacheStorageAllowed 
and instead treats it as NSURLCacheStorageAllowedInMemoryOnly which is pretty 
useless for a persistent cache.

## Goals

 * Build a fully RFC2616 compliant cache instead of doing simple time-based caching
   **Status: Works for general use, some edge cases might not be compliant/implemented yet.**

 * Provide an offline mode to deliver content from cache when no network is available
   **Status: Works fine**

 * Provide a packaging mechanism to pre-populate the cache for accessing content offline
   **Status: Works fine and is used in several real-world apps. A packaging-tool exists in two flavours: Obj-C and python.**

 * Allow caching of UIWebView resources by overriding NSURLCache
   **Status: Works, but since iOS4 there's some trouble with AJAX requests. Might be due to an iOS Bug.**

## Sounds like something I need. Where can I get documentation?

Good question ;) Documentation is always lacking, but you may check the [FAQ](https://github.com/artifacts/AFCache/wiki/FAQ) first.
In the AFCache-iOS Xcode-project you'll find example controllers that use AFCache in different ways.

## Current Version

0.7.2

See CHANGES for release notes.

## History

* Started with master on github after AFCache was already used in some apps.
* Branched to "bip" for two large projects (iOS and OSX) where AFCache was tested quite 
  thorough and gained a lot of it's maturity (e.g. caching on disk, packaging, authentication).
* Added "engine room" for logging (OPTIONAL) in branch bip: https://github.com/bkrpub/EngineRoom
* dropped old master, saved it as branch "pre0.7"
* moved "bip" branch to master, bip might be dropped in the future or might be a playground for new features

## API

The API has changed from master to branch bip, but it should be easy to migrate.
The old master branch moved to branch "pre0.7", but I strongly suggest you to move ahead and migrate to the new master.

## Project status

AFCache is used in several iPhone applications in several versions. It is constantly evolving and
therefore considered beta. 

Done: <strike>Currently I am doing some major changes and additions like a packaging tool and testing it on two 
large real-world projects (iPhone and OSX apps).</strike>
Done: <strike>After sucessfully integrating AFCache into these projects I'll extend the demos and some documentation to
make it a useful library for the public. The test cases are (still) not maintained very well.</strike>

## Branches

* master: stable, but might not have all cutting-edge features. Xcode4 project, but should work with xcode3.
* xcode3: older project structure (xcode3)
* bip: experimental brach, you might find new features there first.
* pre0.7: before branching a HUGE bunch of new features from bip into master for the first time. For legacy purposes only, will be deleted some day.

## Logging

Logging is achieved via an AFLog macro which is either

* just a replacement for NSLog (or nothing if undef'd)
* a logpoint for EngineRoom, a sophisticated logging framework that enables dynamic logging manipulation at runtime,
  From the EngineRoom docs:
  The basic idea is to make the log message a first class citizen.
  LogPoints are data structures which can be manipulated (i.e. enabled / disabled) at runtime.
  This is achieved by creating static structures in a separate linker segment.
  
  You may checkout EngineRoom here (https://github.com/bkrpub/EngineRoom) and link AFCache against
  it by defining USE_ENGINEROOM and adding EngineRoom-OSX.xcodeproj to your project. 

## Issues (Open)

* Displacement strategy: still commented out, is on top of the refactoring list
* Package file handling strategy not completely clear. Right now, a package is removed right after extracting. One might want to track which packages have been extracted yet. This also has to play nice with the file displacement strategy.

* still very unhappy with the cleanup method. Need a clever displacement algorithm here.
* the code to determine cache file size on disk is commented out, because there's a bug in it. Don't use this release for production.

* synchronized requests are not testet well
* instead of using a php script for the server part, an integrated http server for unit testing might be better. Maybe also mock objects for NSResponse objects could do it.
* Maybe the mimetype should be added to the manifest file?
* Make encryption optional. Right now, there's encryption code in the zip classes.

## Issues (Done)

* Big file should be streamed to disk directly instead of holding them in an AFCacheableItem in memory.
* The OSX framework and the iOS library are now seperate Xcode-projects, which is less hassle.

## Anatomy of the manifest file

The afcache.manifest file contains an entry for every file contained in the archive. One entry looks like this:

URL ; last-modified ; expires\n ; mimetype

Note the delimiter, which is " ; " (space semicolon space)
The mimetype is optional.

Example:

http://upload.wikimedia.org/wikipedia/commons/6/63/Wikipedia-logo.png ; Sat, 27 Mar 2004 18:43:30 GMT+00:00 ; Thu, 29 Jul 2010 14:17:20 GMT+00:00 ; text/html

The URL MUST ne properly encoded and MUST NOT contain a hash at the end or parameters.

Since the file path is calculated based on the URL, it's not necessary to include it in the manifest file.
The dates have to be formatted according to rfc1123. Example: "Wed, 01 Mar 2006 12:00:00 GMT"

## Anatomy of the package zip file

The zip file structure resembles the URL:

hostname/path/to/file.suffix
The zip file contains all files collected by the packager and the manifest file. Optionally, it includes userdata.

## Build notes when using AFCache in your project

You need to link to SystemConfiguration.framework and libz.dylib to compile.
Since AFCache uses Objective-C Categories, you need to add the following options to the linker (Targets/YourProject, Info, Build Settings: "Other linker flags")
-ObjC
-all_load

For more information see: http://developer.apple.com/mac/library/qa/qa2006/qa1490.html


## How to run the unit tests (outdated)

The unit tests currently depend on an existing HTTP-Server e.g. Apache. A simple php script
is provided to answer the requests properly. Put the script on your htdocs directory and
configure the URL in LogicTests.m, e.g.

static NSString *kBaseURL = @"http://127.0.0.1/~mic/afcache/";

For more information see CHANGES.

I am frequently using Charles as an HTTP debugging proxy which is superb for finding irregularities.
http://www.charlesproxy.com/


## Copyright

Copyright 2008, 2009, 2010, 2011 Artifacts - Fine Software Development

http://www.artifacts.de

Authors: 
Michael Markowski (m.markowski@artifacts.de)
Nico Schmidt (Savoy Software)
Björn Kriews (bkr (0x40) jumper.org)
Christian Menschel (post at cmenschel.de)

## License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

