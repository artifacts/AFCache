#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright 2008 Artifacts - Fine Software Development
# http://www.artifacts.de
# Author: Martin Borho (martin@borho.net)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import re
import os
import sys
import time
import logging
import mimetypes
import fnmatch
from urlparse import urlparse
from optparse import OptionParser
from zipfile import ZipFile

rfc1123_format = '%a, %d %b %Y %H:%M:%S GMT+00:00'

# add mimetypes
mimetypes.add_type('application/json', '.json', strict=True)

class AFCachePackager(object):
    
    def __init__(self, **kwargs):
        self.maxage       = kwargs.get('maxage')
        self.baseurl      = kwargs.get('baseurl')
        if not self.baseurl:
            self.baseurl = 'afcpkg://localhost'
        self.lastmodfile  = kwargs.get('lastmodfile')
        self.lastmodplus  = kwargs.get('lastmodplus')
        self.lastmodminus = kwargs.get('lastmodminus')            
        self.folder       = kwargs.get('folder') 
        self.include_all  = kwargs.get('include_all')
        self.outfile      = kwargs.get('outfile')
        if not self.outfile: 
            self.outfile = 'afcache-archive.zip'
        self.max_size     = kwargs.get('max_size')
        self.excludes     = kwargs.get('excludes', [])
        self.mime         = kwargs.get('mime')
        self.errors       = []
        self.logger       = kwargs.get('logger',logging.getLogger(__file__))
        self._check_input()
        
    def _check_input(self):
        if not self.folder:
            self.errors.append('import-folder (--folder) is missing')
        elif not os.path.isdir(self.folder):
            self.errors.append('import-folder does not exists')
            
        if not self.maxage:
            self.errors.append('maxage is missing')        
                    
    def _get_host(self, baseurl):
        p = urlparse(baseurl)
        if p.hostname:
            return p.hostname
        else:
            self.errors.append('baseurl invalid')
            return None
        
    def build_zipcache(self):
                    
        manifest = []
        hostname = self._get_host(self.baseurl)
        
        if self.errors:
            return None

        try:
            zip = ZipFile(self.outfile, 'w')
        except IOError, e:
            self.logger.error('exiting: creation of zipfile failed!')
            return None
        else:        
            for dirpath, dirnames, filenames in os.walk(self.folder):            
                # skip empty dirs
                if not filenames:
                    continue

                for name in filenames:   
                
                    path = os.path.join(dirpath, name)
                    # skip hidden files if
                    if not self.include_all:                
                        if name.startswith('.') or path.find('/.') > -1:
                            self.logger.info("skipping "+path)
                            continue                                
                    
                    # skip big files if
                    if self.max_size and (os.path.getsize(path) > self.max_size):
                        self.logger.info("skipping big file "+path)
                        continue
                    
                    # exclude paths if
                    if self.excludes:
                        exclude_file = None
                        for ex_filter in self.excludes:
                            if fnmatch.fnmatch(path, ex_filter):
                                exclude_file = True
                                self.logger.info("excluded "+path)
                                break
                        if exclude_file: continue
                        
                    # detect mime-type
                    mime_type = ''
                    if self.mime:
                        mime_tuple = mimetypes.guess_type(path, False)
                        if mime_tuple[0]: mime_type = mime_tuple[0]
                        else: self.logger.warning("mime-type unknown: "+path)
                    
                    # handle lastmodified
                    if self.lastmodfile: lastmod = os.path.getmtime(os.path.join(dirpath, name))
                    else: lastmod = time.time()
                        
                    if self.lastmodplus: lastmod += self.lastmodplus
                    elif self.lastmodminus: lastmod -= self.lastmodminus

                    # handle path forms 
                    rel_path = os.path.join(dirpath.replace(os.path.normpath(self.folder),''),name)
                    exported_path = hostname+rel_path

                    # add data
                    self.logger.info("adding "+ exported_path)
                    zip.write(path, exported_path)
    
                    # add manifest line
                    last_mod_date = time.strftime(rfc1123_format,time.gmtime(lastmod))
                    expire_date = time.strftime(rfc1123_format,time.gmtime(lastmod+self.maxage))
                    
                    manifest_line = '%s ; %s ; %s' % (self.baseurl+rel_path, last_mod_date, expire_date)
                    # add mime type
                    if self.mime: 
                        manifest_line += ' ; '+mime_type
                    manifest.append(manifest_line)
                    
            # add manifest to zip
            self.logger.info("adding manifest")
            zip.writestr("manifest.afcache", "\n".join(manifest))     
            return True

def main():

    logging.basicConfig(level=logging.DEBUG,format='%(asctime)s %(levelname)-2s %(message)s')
    logger = logging.getLogger(__file__)

    usage = "Usage: %prog [options]"
    parser = OptionParser(usage)
    parser.add_option("--maxage", dest="maxage", type="int", help="max-age in seconds")
    parser.add_option("--baseurl", dest="baseurl",
                    help="base url, e.g. http://www.foo.bar (WITHOUT trailig slash)")
    parser.add_option("--lastmodifiedfile", dest="lastmodfile", action="store_true",
                    help="use lastmodified from file instead of now")
    parser.add_option("--lastmodifiedplus", dest="lastmodplus", type="int",
                    help="add n seconds to file's lastmodfied date")
    parser.add_option("--lastmodifiedminus", dest="lastmodminus", type="int",
                    help="substract n seconds from file's lastmodfied date")
    parser.add_option("--folder", dest="folder",
                    help="folder containing resources")
    parser.add_option("-a", dest="include_all", action="store_true",
                    help="include all files. By default, files starting with a dot are excluded.")
    parser.add_option("--outfile", dest="outfile",
                        help="Output filename. Default: afcache-archive.zip")                                                
    parser.add_option("--maxItemFileSize", dest="max_size", type="int",
                    help="Maximum filesize of a cacheable item.")                                                
    parser.add_option("--exclude", dest="excludes",action="append",
                    help="Regexp filter for filepaths. Add one --exclude for every pattern.")      
    parser.add_option("--mime", dest="mime", action="store_true",
                    help="add file mime types to manifest.afcache")
                    
                        
    (options, args) = parser.parse_args()
    
    packager = AFCachePackager(
                        maxage=options.maxage,
                        baseurl=options.baseurl,
                        lastmodfile=options.lastmodfile,
                        lastmodplus=options.lastmodplus,                        
                        lastmodminus=options.lastmodminus,            
                        folder=options.folder, 
                        include_all=options.include_all,
                        outfile=options.outfile,
                        max_size=options.max_size,
                        excludes=options.excludes,
                        mime=options.mime,
                        logger=logger
                    )

    packager.build_zipcache()
    if packager.errors:        
        print "Error: "+"\nError: ".join(packager.errors)
    
if __name__ == "__main__":
    main()
