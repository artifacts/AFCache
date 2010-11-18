#!/usr/bin/env python
# -*- coding: utf-8 -*-
import zipfile
import unittest
import os
import sys
import logging

# import AFCachePackager
CURRENT_DIR = os.path.abspath(os.path.dirname(__file__))        
sys.path.append(os.path.dirname(CURRENT_DIR)) 
from afcpkg import AFCachePackager

ZIP_IN = CURRENT_DIR+'/testcase-afpkg/very-simple-content-objc.zip'
ZIP_OUT = CURRENT_DIR+'/testcase-afpkg/very-simple-content-py.zip'

## clean from old testfile
if os.path.exists(ZIP_OUT):
    os.remove(ZIP_OUT)

packager = AFCachePackager( maxage=3600, baseurl='http://localhost', lastmodplus= 60,
                folder=CURRENT_DIR+'/testcase-afpkg/very-simple-content/', 
                outfile=ZIP_OUT,
                max_size=800000)
packager.build_zipcache()    

    
class TestPythonPackager(unittest.TestCase):
    
    def setUp(self):                 
        self.zip_ref = zipfile.ZipFile(ZIP_IN)
        self.zip_py = zipfile.ZipFile(ZIP_OUT)

    def test_building(self):
        self.assertEquals([], packager.errors)        
        
    def test_contents(self):
        # check contents
        ref_files = self.zip_ref.namelist() 
        py_files = self.zip_py.namelist() 
        self.assertEqual(sorted(ref_files), sorted(py_files))

    def test_filesize(self):
        # check file size
        ref_info =  self.zip_ref.getinfo('localhost/html/x.html')   
        py_info =  self.zip_py.getinfo('localhost/html/x.html')   
        self.assertEqual(ref_info.file_size,py_info.file_size)

    def test_manifest(self):
        # check manifest
        ref_manifest = self.zip_ref.read('manifest.afcache').splitlines()
        gen_manifest = self.zip_py.read('manifest.afcache').splitlines()
        self.assertEqual(len(ref_manifest),len(gen_manifest))


if __name__ == '__main__':
    unittest.main()
