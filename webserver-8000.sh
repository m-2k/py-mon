#!/usr/bin/env python

import os
import posixpath
import urllib
import urllib2
import copy
import socket
import json
from urlparse import urlparse, parse_qs
# import itertools # debugging

import string,cgi,time
from os import curdir, sep
from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer

HTTP_PORT = 8000

PATH_ROOT = curdir + sep
PATH_STATIC = PATH_ROOT + 'static' + sep
# ACCESS_CONTROL_ALLOW_ORIGIN = '*'

STATUS_OK = 'OK'
STATUS_UNAVAILABLE = 'UNAVAILABLE'
STATUS_NODE_NOT_DEFINED = 'NODE_NOT_DEFINED'

URL_STATISTICS = '/statistics'
URL_NODE_STATISTICS = '/node-statistics'

NODES=[
    ('aer3','A3',['/','/dev/shm','/proc']),
    ('aer2','A2',['/','/dev/shm','/proc'])
]



class MyHandler(BaseHTTPRequestHandler):
    def mount_statistics(self, mount):
        try:
            s = os.statvfs(mount)
        except OSError:
            print "VOLUME NOT FOUND: %s" % vol
            return {'mount': mount, 'status': STATUS_UNAVAILABLE}
        else:
            print "VOLUME: %s %s" % (s.f_bavail,s.f_blocks)
            if s.f_blocks == 0:
                percent = 100.0
            else:
                percent = 100.0 - (s.f_bavail / (s.f_blocks / 100.0))
            p_formatted = str(int(percent)) if (int(percent * 10)/10) == 0 or percent % 10 == 0 else "%.1f" % percent
            mnt_size = s.f_bavail * s.f_frsize
            return {'mount': mount, 'status': STATUS_OK, 'percent': percent, 'perc_formatted': p_formatted, 'mnt_size': mnt_size}
    def mounts_statistics(self, (hostname, publicname, mounts)):
        scope = []
        for mount in mounts:
            scope.append(self.mount_statistics(mount))
        return scope
    def load_average(self):
        return os.getloadavg()
    def full_statistics(self, node):
        if type(node) is tuple:
            return {'status': STATUS_OK, 'mounts': self.mounts_statistics(node), 'loadavg': self.load_average()}
        else:
            return {'status': STATUS_NODE_NOT_DEFINED}
    def do_GET(self):
        (path, qs) = (urlparse(self.path).path, parse_qs(urlparse(self.path).query))
        print "Parse: %s <<>> %s" % (path, qs) # qs.__class__.__name__
        # print "ENDSWITH: %s" % path.endswith(".css")
        selfhostname = socket.gethostname()
        
        try:
            if path.endswith(".js"):
                f = open(PATH_STATIC + path)
                self.send_response(200)
                self.send_header('Content-type', 'text/css')
                self.end_headers()
                self.wfile.write(f.read())
                f.close()
                return
            if path.endswith(".html"):
                f = open(PATH_STATIC + path)
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                self.wfile.write(f.read())
                f.close()
                return
            if path == URL_STATISTICS and qs == {}:
                print "COLLECTING STATISTIC..."
                
                data = []
                for node in NODES:
                    (hostname, publicname, mounts) = node
                    if hostname == selfhostname:
                        fullstat=self.full_statistics(node)
                        fullstat['node']=hostname
                        data.append(fullstat)
                    else:
                        print "GET FROM EXTERNAL host: %s" % hostname
                        external_data=urllib2.urlopen("http://%s:8000%s" % (hostname, URL_NODE_STATISTICS)).read()
                        external_data_native=json.loads(external_data)
                        external_data_native['node']=hostname
                        data.append(external_data_native)
                print "COLLECTING STATISTIC [OK]"
                self.wfile.write(json.dumps(data))
                return
            if path == URL_NODE_STATISTICS and qs == {}:
                for node in NODES:
                    (hostname, publicname, mounts) = node
                    if hostname == selfhostname:
                        print "STAT: %s %s" % (node,self.full_statistics(node))
                        self.wfile.write(json.dumps(self.full_statistics(node)))
                        return
                return self.wfile.write(json.dumps(self.full_statistics(None)))
            return
        except IOError:
            self.send_error(404,'File Not Found: %s' % self.path)

def main():
    try:
        server = HTTPServer(('', HTTP_PORT), MyHandler)
        print "Starting on port %s" % HTTP_PORT
        server.serve_forever()
    except KeyboardInterrupt:
        print '^C received, shutting down server'
        server.socket.close()

if __name__ == '__main__':
    main()

