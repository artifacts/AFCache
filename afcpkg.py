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


import os
import sys
import time
import logging
from urlparse import urlparse
from optparse import OptionParser
from zipfile import ZipFile

rfc1123_format = '%a, %d %b %Y %H:%M:%S GMT+00:00'
logging.basicConfig(level=logging.DEBUG,format='%(asctime)s %(levelname)-2s %(message)s')

def get_host(baseurl):
    p = urlparse(baseurl)
    if p.hostname:
        return p.hostname
    else:
        sys.exit('baseurl invalid')
    
def build_zipcache(options):
    manifest = []
    hostname = get_host(options.baseurl)
    try:
        zip = ZipFile(options.outfile, 'w')
    except IOError, e:
        sys.exit('exiting: creation of zipfile failed!')
    else:        
        for dirpath, dirnames, filenames in os.walk(options.folder):            
            # skip empty dirs
            if not filenames:
                continue

            for name in filenames:   
            
                path = os.path.join(dirpath, name)
                # skip hidden files if
                if not options.include_all:                
                    if name.startswith('.') or path.find('/.') > -1:
                        logging.info("skipping "+path)
                        continue                                
                
                # skip big files if
                if options.max_size and (os.path.getsize(path) > options.max_size):
                    logging.info("skipping big file "+path)
                    continue
                    
                # handle lastmodified
                lastmod = os.path.getmtime(os.path.join(dirpath, name))
                if options.lastmodplus: lastmod += options.lastmodplus
                elif options.lastmodminus: lastmod -= options.lastmodminus
                
                # handle path forms 
                rel_path = os.path.join(dirpath.replace(os.path.normpath(options.folder),''),name)
                exported_path = hostname+rel_path

                # add data
                logging.info("adding "+ exported_path)
                zip.write(path, exported_path)
  
                # add manifest line
                last_mod_date = time.strftime(rfc1123_format,time.gmtime(lastmod))
                expire_date = time.strftime(rfc1123_format,time.gmtime(lastmod+options.maxage))  
                manifest.append('%s ; %s ; %s' % (options.baseurl+rel_path, last_mod_date, expire_date))
                
        # add manifest to zip
        logging.info("adding manifest")
        zip.writestr("manifest.afcache", "\n".join(manifest))     
        

def main():

    usage = "Usage: %prog [options]"
    parser = OptionParser(usage)
    parser.add_option("--maxage", dest="maxage", type="int", help="max-age in seconds")
    parser.add_option("--baseurl", dest="baseurl",
                    help="base url, e.g. http://www.foo.bar (WITHOUT trailig slash)")
    parser.add_option("--lastmodifiedplus", dest="lastmodplus", type="int",
                    help="add n seconds to file's lastmodfied date")
    parser.add_option("--lastmodifiedminus", dest="lastmodminus", type="int",
                    help="substract n seconds from file's lastmodfied date")
    parser.add_option("--folder", dest="folder",
                    help="folder containing resources")
    parser.add_option("-a", dest="include_all", action="store_true",
                    help="include all files. By default, files starting with a dot are excluded.")
    parser.add_option("--outfile", dest="outfile", default="afcache-archive.zip",  
                        help="Output filename. Default: afcache-archive.zip")                                                
    parser.add_option("--maxItemFileSize", dest="max_size", type="int",
                    help="Maximum filesize of a cacheable item.")                                                
                        
    (options, args) = parser.parse_args()

    errors = []    
    if not options.folder:
        errors.append('import-folder (--folder) is missing')
    elif not os.path.isdir(options.folder):
        errors.append('import-folder does not exists')
        
    if not options.outfile:
        errors.append('output file is missing')
        
    if not options.maxage:
        errors.append('maxage is missing')        
    
    if not options.baseurl:
        errors.append('baseurl is missing')
     
    if errors:        
        sys.exit("\n".join(errors))
        
    build_zipcache(options)
    
if __name__ == "__main__":
    main()
