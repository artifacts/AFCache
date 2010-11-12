#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os
import sys
from urlparse import urlparse
from optparse import OptionParser
from zipfile import ZipFile

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
            for name in filenames:      
                rel_path = os.path.join(dirpath.replace(options.folder,'/'),name)
                exported_path = os.path.join(hostname, rel_path)
                path = os.path.join(dirpath, name)
                zip.write(path, exported_path)
                manifest.append(options.baseurl+rel_path)
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
    
    if not options.baseurl:
        errors.append('baseurl is missing')
     
    if errors:        
        sys.exit("\n".join(errors))
        
    build_zipcache(options)
    
if __name__ == "__main__":
    main()
