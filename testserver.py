#! /usr/bin/env python

import time
import BaseHTTPServer
import urlparse

HOST_NAME = 'localhost'
PORT_NUMBER = 49000

def makeBestType(s):
	try:
		return int(s)
	except:
		pass

	try:
		return float(s)
	except:
		pass

	return s

def sendFile(s, numBytes=100, delay=0.0, blockSize=100):
	s.send_response(200)
	s.send_header("Content-type", "text/html")
	s.send_header("Content-Length", "%d" % numBytes)
	s.end_headers()

	sentBytes = 0
	
	while sentBytes < numBytes:
		time.sleep(delay)
		actualBytes = (sentBytes + blockSize)
		if actualBytes > numBytes:
			actualBytes = numBytes

		s.wfile.write("a" * (actualBytes - sentBytes))
		s.wfile.flush()

		sentBytes = actualBytes
		print sentBytes

responses = {
	"/file" : sendFile
}

class MyHandler(BaseHTTPServer.BaseHTTPRequestHandler):
	def do_HEAD(self):
		self.send_response(200)
		self.send_header("Content-type", "text/html")
		self.end_headers()

	def do_GET(self):
		"""Respond to a GET request."""

		if self.headers.has_key('If-Modified-Since'):
			self.send_response(304)
			return

		components = urlparse.urlsplit(self.path)
		path = components[2]
		params = components[3].split('&')
		print params
		parameters = {}
		for p in params:
			k, v = p.split('=')
			v = makeBestType(v)
			parameters[k] = v
		if responses.has_key(path):
			responses[path](self, **parameters)

if __name__ == '__main__':
	server_class = BaseHTTPServer.HTTPServer
	httpd = server_class((HOST_NAME, PORT_NUMBER), MyHandler)
	try:
		httpd.serve_forever()
	except KeyboardInterrupt:
		pass
	httpd.server_close()
