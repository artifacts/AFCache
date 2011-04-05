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

// deprecated. Use cachedObjectForURLSynchroneous: which is public api now.
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url options: (int) options DEPRECATED_ATTRIBUTE;

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url;
- (void)setObject: (AFCacheableItem *) obj forURL: (NSURL *) url;
- (NSString *)filenameForURL: (NSURL *) url;
- (NSString *)filenameForURLString: (NSString *) URLString;
- (NSString *)filePath: (NSString *) filename;
- (NSString *)filePathForURL: (NSURL *) url;
- (NSDate *) getFileModificationDate: (NSString *) filePath;
- (NSUInteger)numberOfObjectsInDiskCache;
- (void)removeReferenceToConnection: (NSURLConnection *) connection;
- (void)reinitialize;
- (uint32_t)hash:(NSString*)str;
//- (void)removeObjectForURLString: (NSString *) URLString fileOnly:(BOOL) fileOnly;
- (void)removeCacheEntryWithFilePath:(NSString*)filePath fileOnly:(BOOL) fileOnly;
- (void)removeItemsForURL:(NSURL*)url;
- (void)removeItemForURL:(NSURL*)url itemDelegate:(id)itemDelegate;
- (NSFileHandle*)createFileForItem:(AFCacheableItem*)cacheableItem;
- (void)addItemToDownloadQueue:(AFCacheableItem*)item;
- (void)removeFromDownloadQueue:(AFCacheableItem*)item;
- (void)removeFromDownloadQueueAndLoadNext:(AFCacheableItem*)item;
- (void)fillPendingConnections;
- (BOOL)isQueuedURL:(NSURL*)url;
- (void)downloadNextEnqueuedItem;
- (void)downloadItem:(AFCacheableItem*)item;
- (void)registerItem:(AFCacheableItem*)item;
- (void)signalItemsForURL:(NSURL*)url usingSelector:(SEL)selector;
- (void)setContentLengthForFile:(NSString*)filename;
- (void)cancelConnectionsForURL: (NSURL *) url;
@end

@interface AFCacheableItem (PrivateAPI)

@property (nonatomic, assign) int tag;

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
