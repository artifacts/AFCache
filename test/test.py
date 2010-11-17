#!/usr/bin/env python
# -*- coding: utf-8 -*-
import zipfile
import unittest
import os

'''
add afcpkg to your path and run the command in afcpkg-call-py

afcpkg.py --maxage 3600 --folder testcase-afpkg/very-simple-content/ \
--outfile testcase-afpkg/very-simple-content-py.zip --baseurl http://localhost  \
--lastmodifiedplus 60 --maxItemFileSize 800000

'''
class TestPythonPackager(unittest.TestCase):
    
    def setUp(self):
        pwd = os.path.abspath(os.path.dirname(__file__))        
        self.zip_ref = zipfile.ZipFile(pwd+'/testcase-afpkg/very-simple-content-objc.zip')
        self.zip_py  = zipfile.ZipFile(pwd+'/testcase-afpkg/very-simple-content-py.zip')

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
        ref_manifest = sorted(self.zip_ref.read('manifest.afcache').splitlines())
        gen_manifest = sorted(self.zip_py.read('manifest.afcache').splitlines())
        self.assertEqual(ref_manifest,gen_manifest)


if __name__ == '__main__':
    unittest.main()
