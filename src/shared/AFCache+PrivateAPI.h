/*
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
 */

#import "AFCache.h"

@class AFCache;
@class AFCacheableItem;

@interface AFCache (PrivateAPI)

- (void)updateModificationDataAndTriggerArchiving:(AFCacheableItem *)obj;


- (void)setConnectedToNetwork:(BOOL)connected;
- (void)reinitialize;
- (void)removeCacheEntryWithFilePath:(NSString*)filePath fileOnly:(BOOL) fileOnly;

- (NSFileHandle*)createFileForItem:(AFCacheableItem*)cacheableItem;
- (void)addItemToDownloadQueue:(AFCacheableItem*)item;
- (BOOL)isQueuedURL:(NSURL*)url;
- (uint64_t)setContentLengthForFile:(NSString*)filename;
- (BOOL)_fileExistsOrPendingForCacheableItem:(AFCacheableItem*)item;
- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL) fileOnly;
- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL) fileOnly fallbackURL:(NSURL *)fallbackURL;

// TODO: This getter to its property is necessary as the category "Packaging" needs to access the private property. This is due to Packaging not being a real category
- (NSOperationQueue*) packageArchiveQueue;

@end

@interface AFCacheableItem (PrivateAPI)

- (void)setDownloadStartedFileAttributes;
- (void)setDownloadFinishedFileAttributes;
- (BOOL)isQueuedOrDownloading;
- (BOOL)hasDownloadFileAttribute;
- (BOOL)hasValidContentLength;
- (uint64_t)getContentLengthFromFile;
- (void)appendData:(NSData*)newData;

// Making synthesized getter and setter for private property public for private API
- (void)setHasReturnedCachedItemBeforeRevalidation:(BOOL)value;
- (BOOL)hasReturnedCachedItemBeforeRevalidation;

@end

@interface AFCacheableItemInfo (PrivateAPI)

- (NSString*)newUniqueFilename;

@end
