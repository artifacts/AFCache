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

- (NSMutableDictionary *)CACHED_OBJECTS;

- (NSMutableDictionary *)CACHED_REDIRECTS;

- (void)updateModificationDataAndTriggerArchiving:(AFCacheableItem *)obj;


- (void)setConnectedToNetwork:(BOOL)connected;
- (void)removeReferenceToConnection: (NSURLConnection *) connection;
- (void)reinitialize;
- (void)removeCacheEntryWithFilePath:(NSString*)filePath fileOnly:(BOOL) fileOnly;

#pragma mark - Pending client items (Non-fully processed pending AFCacheableItem entries requested by the AFCache client)
- (void)removeClientItemsForURL:(NSURL*)url;
- (void)removeClientItemForURL:(NSURL*)url itemDelegate:(id)itemDelegate;
- (void)signalClientItemsForURL:(NSURL*)url usingSelector:(SEL)selector;

- (NSFileHandle*)createFileForItem:(AFCacheableItem*)cacheableItem;
- (void)addItemToDownloadQueue:(AFCacheableItem*)item;
- (void)removeFromDownloadQueue:(AFCacheableItem*)item;
- (void)fillPendingConnections;
- (BOOL)isQueuedURL:(NSURL*)url;
- (void)downloadNextEnqueuedItem;
- (void)downloadItem:(AFCacheableItem*)item;
- (void)registerClientItem:(AFCacheableItem*)item;
- (uint64_t)setContentLengthForFile:(NSString*)filename;
- (void)cancelConnectionsForURL: (NSURL *) url;
- (BOOL)_fileExistsOrPendingForCacheableItem:(AFCacheableItem*)item;
- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL) fileOnly;
- (void)removeCacheEntry:(AFCacheableItemInfo*)info fileOnly:(BOOL) fileOnly fallbackURL:(NSURL *)fallbackURL;

// TODO: This getter to its property is necessary as the category "Packaging" needs to access the private property. This is due to Packaging not being a real category
- (NSOperationQueue*) packageArchiveQueue;

@end

@interface AFCacheableItem (PrivateAPI)

- (void)setDownloadStartedFileAttributes;
- (void)setDownloadFinishedFileAttributes;
- (BOOL)isDownloading;
- (BOOL)hasDownloadFileAttribute;
- (BOOL)hasValidContentLength;
- (uint64_t)getContentLengthFromFile;
- (void)appendData:(NSData*)newData;
- (void)signalItems:(NSArray*)items usingSelector:(SEL)selector;
- (void)signalItemsDidFinish:(NSArray*)items;
- (void)signalItemsDidFail:(NSArray*)items;

@end

@interface AFCacheableItemInfo (PrivateAPI)

- (NSString*)newUniqueFilename;

@end
