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

@interface AFCache (PrivateExtensions)

- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url options: (int) options;
- (AFCacheableItem *)cachedObjectForURL: (NSURL *) url;
- (void)setObject: (AFCacheableItem *) obj forURL: (NSURL *) url;
- (NSString *)filenameForURL: (NSURL *) url;
- (NSString *)filePath: (NSString *) filename;
- (NSString *)filePathForURL: (NSURL *) url;
- (AFCacheableItem *)cacheableItemFromCacheStore: (NSURL *) url;
- (NSDate *) getFileModificationDate: (NSString *) filePath;
- (int)numberOfObjectsInDiskCache;
- (void)removeReferenceToConnection: (NSURLConnection *) connection;
- (void)cancelConnectionsForURL: (NSURL *) url;
- (void)reinitialize;

@end