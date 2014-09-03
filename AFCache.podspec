Pod::Spec.new do |s|

  s.name         = "AFCache"
  s.version      = "0.10.1"
  s.summary      = "AFCache is an HTTP disk cache for use on iPhone/iPad and OSX."

  s.description  = <<-DESC
	AFCache is an HTTP disk cache for use on iPhone/iPad and OSX. It can be linked as a static library or as a framework. 
	The cache was initially written because on iOS, NSURLCache ignores NSURLCacheStorageAllowed and instead treats it as 
	NSURLCacheStorageAllowedInMemoryOnly which is pretty useless for a persistent cache.
                   DESC

  s.homepage     = "https://github.com/artifacts/AFCache"
  s.license      = 'Apache'

  s.authors      = { "Michael Markowski" => "m.markowski@artifacts.de", "Nico Schmidt" => "", "Björn Kriews" => "bkr@jumper.org", "Christian Menschel" => "post@cmenschel.de" }


  s.ios.deployment_target = '5.0'
  s.osx.deployment_target = '10.7'

  s.source       = { :git => "https://github.com/artifacts/AFCache.git", :tag => s.version.to_s }

  s.source_files  = 'src/shared/**/*.{h,m}', 'src/3rdparty/AFRegexString/**/*.{h,m}'
  s.ios.source_files  = 'src/iOS/**/*.{h,m}'
  s.osx.source_files  = 'src/OSX/**/*.{h,m}'

  s.exclude_files = 'src/OSX/afcpkg_main*', '**/main.{h,m}'

  s.requires_arc = true

  # s.framework  = 'SomeFramework'
  # s.frameworks = 'SomeFramework', 'AnotherFramework'

  # s.library   = 'iconv'
  # s.libraries = 'iconv', 'xml2'

  # s.xcconfig = { 'HEADER_SEARCH_PATHS' => '$(SDKROOT)/usr/include/libxml2' }
  s.dependency 'ZipArchive', '~> 1.3.0'
end
