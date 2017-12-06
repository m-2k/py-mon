#!/usr/bin/env python
# Martemyanov Andrey

import os
import sys
import posixpath
import urllib
import urllib2
import copy
import socket
import json
import threading
import Queue
import time
import datetime
import subprocess
# import re
from urlparse import urlparse, parse_qs
# import itertools # debugging

import string,cgi,time
from os import curdir, sep
from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer

HTTP_PORT = 8001
LOCALHOST_DEVELOPING = True
SERVE_STATIC = True

PATH_ROOT = curdir + sep
PATH_STATIC = PATH_ROOT + 'static' + sep
# ACCESS_CONTROL_ALLOW_ORIGIN = '*'

STATUS_OK = 'OK'
STATUS_UNAVAILABLE = 'UNAVAILABLE'
STATUS_NODE_NOT_DEFINED = 'NODE_NOT_DEFINED'

URL_STATISTICS = '/statistics'
URL_NODE_STATISTICS = '/node-statistics'

NODES=[
    ('localhost','lo',['/'],[8000],"http://localhost:8000/en","Erlang"),
    ('aer15','aer15',['/opt/bbap','/opt'],[80,8880],"http://aer15/portalserver/static/sb-bundle/images/main-logo.png","Nginx")
    # ('aer14','aer15',['/opt/bbap','/opt'],[80,8880],"http://aer15/portalserver/static/sb-bundle/images/main-logo.png","Nginx"),
    # ('aer15','aer15',['/opt/bbap','/opt'],[81,8880],"http://aer15/portalserver/static/sb-bundle/images/main-logo.png1","Nginx")
]

class MyHandler(BaseHTTPRequestHandler):
    def mount_statistics(self, mount):
        try:
            s = os.statvfs(mount)
        except OSError:
            print "[ERR] VOLUME NOT FOUND: %s" % mount
            return {'mount': mount, 'status': STATUS_UNAVAILABLE}
        else:
            print "VOLUME: %s %s" % (s.f_bavail,s.f_blocks)
            if s.f_blocks == 0:
                percent = 100.0
            else:
                percent = 100.0 - (s.f_bavail / (s.f_blocks / 100.0))
            p_formatted = str(int(percent)) if (int(percent * 10)/10) == 0 or percent % 10 == 0 else "%.1f" % percent
            mnt_size = s.f_bavail * s.f_frsize
            print "VOLUME FOUND: %s" % p_formatted
            return {'mount': mount, 'status': STATUS_OK, 'percent': round(percent,5), 'perc_formatted': p_formatted, 'mnt_size': mnt_size}
    def mounts_statistics(self, (hostname,publicname,mounts,ports,check_url,check_desc)):
        scope = []
        print "mounts_statistics %s" % hostname
        for mount in mounts:
            scope.append(self.mount_statistics(mount))
        return scope
    def load_average(self):
        [a,b,c] = os.getloadavg()
        return ["%.1f" % a,"%.1f" % b,"%.1f" % c]
    def resource_available(self,url):
        print "resource_available: %s" % (url)
        user_agent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        values = {} # VALUES FOR POST-HTTP-METHOD
        headers = { 'User-Agent' : user_agent, 'Cache-Control' : 'no-cache' }

        data = urllib.urlencode(values)
        # req = urllib2.Request(url, data, headers)
        req = urllib2.Request(url)
        try:
            start = time.time()
            response = urllib2.urlopen(req)
            end = time.time()
            the_page = response.read()
            code=response.getcode()
            return (code,end-start,the_page)
        except urllib2.HTTPError as e:
            print "[ERR] HTTPError: %s %s" % (url,e.code)
            return (e.code,0,"")
        except urllib2.URLError as e:
            print "[ERR] URLError: %s %s " % (e.reason.errno,e.reason.strerror)
            return (e.reason.errno,0,e.reason.strerror)
    def socket_available(self,port):
        s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        r=s.connect_ex(('127.0.0.1',port))
        s.close()
        return {'port': port, 'is_used': True if r==0 else False}
    def sockets_available(self, (hostname,publicname,mounts,ports,check_url,check_desc)):
        scope = []
        for port in ports:
            scope.append(self.socket_available(port))
        return scope
    def health_check(self,url):
        (code,time,data)=self.resource_available(url)
        
        data=data.replace("\n", "").replace("\r", "").replace("\t", "")[:16] if code == 200 else data
        
        print "health_check: %s %s %s" % (code,time,data)
        return (code,time,data)
        # return (code,time,"")
    def local_statistics(self, node):
        
        # try:
        #     cpu=mq.get(block=True,timeout=0.001)
        # except Queue.Empty:
        #     cpu=None
        
        cpu = last_collector_value
            
        print "MQ last value: %s" % cpu
        # print "MQ last value: %s" % None if mq.empty() else mq.get()
        # print "MQ size: %s" % mq.qsize()
        
        
        
        if type(node) is tuple:
            return {'status':STATUS_OK,'mounts':self.mounts_statistics(node),
                'loadavg':self.load_average(),'ports':self.sockets_available(node),
                'cpu':cpu}
        else:
            return {'status': STATUS_NODE_NOT_DEFINED}
    def is_localhost(self,name):
        if LOCALHOST_DEVELOPING == True:
            try:
                return socket.gethostbyname(name)[:4] == '127.'
            except:
                return False
        else:
            return socket.gethostname() == name
    def do_GET(self):
        (path, qs) = (urlparse(self.path).path, parse_qs(urlparse(self.path).query))
        print "Parse: %s <<>> %s" % (path, qs) # qs.__class__.__name__
        # print "ENDSWITH: %s" % path.endswith(".css")

        try:
            if path.endswith(".js") and SERVE_STATIC == True:
                f = open(PATH_STATIC + path)
                self.send_response(200)
                self.send_header('Content-type', 'text/css')
                self.end_headers()
                self.wfile.write(f.read())
                f.close()
                return
            if path.endswith(".html") and SERVE_STATIC == True:
                f = open(PATH_STATIC + path)
                self.send_response(200)
                self.send_header('Content-type', 'text/html')
                self.end_headers()
                self.wfile.write(f.read())
                f.close()
                return
            if path == URL_STATISTICS and qs == {}:
                print "COLLECTING STATISTIC..."
                
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                
                data = []
                for node in NODES:
                    (hostname,publicname,mounts,ports,check_url,check_desc) = node
                    if self.is_localhost(hostname):
                        print "GET FROM LOCAL host: %s" % hostname
                        node_dict=self.local_statistics(node)
                    else:
                        print "GET FROM EXTERNAL host: %s" % hostname
                        (code,time,external_data)=self.resource_available("http://%s:%s%s" % (hostname,HTTP_PORT,URL_NODE_STATISTICS))
                        if code == 200:
                            print "EXTERNAL HOST OK: %s %s %s" % (code,time,external_data)
                            node_dict=json.loads(external_data)
                        else:
                            print "[ERR] EXTERNAL HOST UNAVAILABLE: %s %s" % (hostname,code)
                            node_dict={'status': STATUS_UNAVAILABLE}
                    node_dict['node']=hostname
                    node_dict['desc']=check_desc
                    print "CHECK URL : %s" % check_url
                    if check_url != None:
                        (ck_code,ck_time,ck_data)=self.health_check(check_url)
                        node_dict['code']=ck_code
                        node_dict['time']=ck_time
                        node_dict['data']=ck_data
                    data.append(node_dict)
                print "COLLECTING STATISTIC [OK]"
                self.wfile.write(json.dumps(data))
                return
            if path == URL_NODE_STATISTICS and qs == {}:
                print "COLLECTING NODE-STATISTIC..."
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                for node in NODES:
                    (hostname, publicname, mounts,check_url,check_desc) = node
                    if self.is_localhost(hostname):
                        print "STAT: %s %s" % (node,self.local_statistics(node))
                        self.wfile.write(json.dumps(self.local_statistics(node)))
                        print "COLLECTING NODE-STATISTIC... [OK]"
                        return
                self.wfile.write(json.dumps(self.local_statistics(None)))
                return 
            return
        except IOError:
            self.send_error(404,'File Not Found: %s' % self.path)



def background_collector(mq):
    global last_collector_value
    while True:
        # with mq.mutex:
        #     mq.queue.clear() # thread-safe clear queue
        
        cmd = {
            'darwin': "sar 5 1 |tail -1|awk '{print $2}'" # macosx
        }
        default_cmd = "sar 5 1 |tail -1|awk '{print $3}'" # linux2
        
        p = subprocess.Popen(cmd.get(sys.platform,default_cmd), shell=True,stdout=subprocess.PIPE)
        output, err = p.communicate()
                
        # mq.put(output.strip())
        last_collector_value = output.strip()
        # time.sleep(5) # float seconds



if __name__ == '__main__':
    mq = Queue.Queue() # multi-process queue
    last_collector_value = None # unsafe for many processes
    collector_t = threading.Thread(target=background_collector, args = (mq,))
    collector_t.daemon = True
    collector_t.start()
    
    try:
        server = HTTPServer(('', HTTP_PORT), MyHandler)
        print "Starting on port %s" % HTTP_PORT
        server.serve_forever()
    except KeyboardInterrupt:
        print '^C received, shutting down server'
        server.socket.close()

