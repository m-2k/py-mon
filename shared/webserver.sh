#!/usr/bin/env python
# https://github.com/m-2k/py-mon

import os
import sys
#import signal
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
from collections import namedtuple

import string,cgi,time
from os import curdir, sep
from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer

try:
    import cx_Oracle
except ImportError:
    cx_Oracle = False

try:
    import pyodbc
except ImportError:
    pyodbc = False

try:
    import psutil
except ImportError:
    psutil = False

PYMON_VERSION = '2f'

###PATH_PID_FILE = '/tmp/py-mon.pid'
HTTP_PORT = 8001
LOCALHOST_DEVELOPING = False
SERVE_STATIC = False

PATH_ROOT = curdir + sep
PATH_STATIC = PATH_ROOT + 'static' + sep
# ACCESS_CONTROL_ALLOW_ORIGIN = '*'

STATUS_OK = 'OK'
STATUS_UNAVAILABLE = 'UNAVAILABLE'
STATUS_NODE_NOT_DEFINED = 'NODE_NOT_DEFINED'
STATUS_CMD_WRONG = 'CMD_WRONG'
TYPE_REQ = 'REQUEST'
TYPE_CMD = 'COMMAND'

URL_STATISTICS = '/statistics'
URL_NODE_STATISTICS = '/node-statistics'
URL_CMD_STOP_ALL = '/cmd-stop-all'
URL_CMD_STOP = '/cmd-stop'

IS_ENABLED = True

###Mount = namedtuple('Mount', 'path name')
###Mount.__new__.__defaults__ = ('',None)

###Port = namedtuple('Port', 'name number')
###Port.__new__.__defaults__ = ('',None)

Url = namedtuple('Url', 'name address')
Url.__new__.__defaults__ = ('',None)

Db = namedtuple('Db', 'name type connect query')
Db.__new__.__defaults__ = ('',None,None,None)

Node = namedtuple('Node', 'host desc group mounts ports urls dbs')
Node.__new__.__defaults__ = ('','','',[],[],[],[])

NODES=[ 
    Node('geat1','geat1','g1',['/usr/ibm','/tmp'],[9080,9082],[Url('WAS','http://geat1:9080/static/healthCheck.jsp')]),
    Node('geat2','geat2','g1',['/usr/ibm','/tmp'],[9080,9082],[Url('WAS','http://geat2:9080/static/healthCheck.jsp')]),
    Node('geat5','geat5','g2',['/usr/ibm','/tmp'],[9080,9082],[Url('WAS','http://geat5:9080/static/healthCheck.jsp')]),
    Node('geat6','geat6','g2',['/usr/ibm','/tmp'],[9080,9082],[Url('WAS','http://geat6:9080/static/healthCheck.jsp')]),
    Node('geat9','geat9','g3',['/usr/ibm','/tmp','/opt','/opt/SASGateway','/import_nsi'],[9080,9082],
        [Url('WAS','http://geat9:9080/rest/dictionary/dictionaries/DICT_SYSTEM'),
        Url('BoundsErr','http://geat9:9080/errors'),Url('Bounds','http://geat9:9080/entities')]),
    Node('geat15','geat15','g8',['/opt/nginx','/tmp'],[80],[Url('Nginx','http://geat15/static/images/main-logo.png')]),
    Node('geat16','geat16','g8',['/opt/nginx','/tmp'],[80],[Url('Nginx','http://geat16/static/images/main-logo.png')]),
    Node('geat13','geat13','g9',['/opt/tomcat','/tmp'],[8983],[Url('Solr','http://geat13:8983/solr')]),
    Node('geat14','geat14','g9',['/opt/tomcat','/tmp'],[8983],[Url('Solr','http://geat14:8983/solr')])
]

#### ODBC_1 = Db('servername','odbc',
####     'DRIVER={SQL SERVER};SERVER=servername\instance;DATABASE=database;UID=user;PWD=passwd',
####     "select accountid from database.dbo.user_login where login = 'user'")
#### 
#### ORA_1 = Db('dbname','ora',
####     'user/passwd@IPADDRESS/schema',
####     "select user_domain from dim_user t where user_id = 1")
####
#### NODES=[
####     Node('hostname','description','g1',['c:','d:','f:'],[80,443],[Url('descriptionUrl','http://hostname2/path/')],[ODBC_1]),
####     Node('hostname2','description2','g1',['c:','d:'],[80,443],[Url('descriptionUrl2','http://hostname3/path/')],[ODBC_3])
#### ]

def is_localhost(name):
    if LOCALHOST_DEVELOPING == True:
        try:
            return socket.gethostbyname(name)[:4] == '127.'
        except:
            return False
    else:
        ### return socket.gethostname() == name
        return socket.getfqdn().upper() == name.upper()

class MyHandler(BaseHTTPRequestHandler):

    ### allow_reuse_address = True
    #def log_message(self, format, *args):
    #    None
    #    print "%s - - [%s] %s\n" % (self.address_string(),self.log_date_time_string(),format%args)
    def mount_statistics(self, mount): ### TODO: refactor
        if psutil:
            try:
                s = psutil.disk_usage(mount)
            except OSError:
                print "[ERR] VOLUME ERROR: %s" % mount
                return {'mount': mount, 'status': STATUS_UNAVAILABLE}
            else:
                p = s.percent
                pf = str(int(p)) if (int(p * 10)/10) == 0 or p % 10 == 0 else "%.1f" % p
                return {
                    'mount': mount,
                    'status': STATUS_OK,
                    'percent': round(s.percent,5),
                    'perc_formatted': pf,
                    'size_total': s.total,
                    'size_free': s.free }
        else:
            try:
                s = os.statvfs(mount)
            except OSError:
                print "[ERR] VOLUME ERROR: %s" % mount
                return {'mount': mount, 'status': STATUS_UNAVAILABLE}
            else:
                if s.f_blocks == 0:
                    percent = 100.0
                else:
                    percent = 100.0 - (s.f_bavail / (s.f_blocks / 100.0))
                p_formatted = str(int(percent)) if (int(percent * 10)/10) == 0 or percent % 10 == 0 else "%.1f" % percent
                mnt_size = s.f_bavail * s.f_frsize
                return {
                    'mount': mount,
                    'status': STATUS_OK,
                    'percent': round(percent,5),
                    'perc_formatted': p_formatted,
                    'size_total': mnt_size,
                    'size_free': 0 }
    def load_average(self):
        if sys.platform == 'win32':
            return None
        else:
            return os.getloadavg()
    def resource_available(self,url):
        # print "resource_available: %s" % (url)
        #user_agent = 'Mozilla/4.0 (compatible; MSIE 5.5; Windows NT)'
        # values = {} # VALUES FOR POST-HTTP-METHOD
        # headers = { 'User-Agent' : user_agent, 'Cache-Control' : 'no-cache' }

        # data = urllib.urlencode(values)
        # req = urllib2.Request(url, data, headers)
        req = urllib2.Request(url)
        r = {}
        try:
            start = time.time()
            response = urllib2.urlopen(req, timeout = 2)
            end = time.time()
            the_page = response.read()
            code=response.getcode()
            mime=response.info().type
            return (code,end-start,the_page,0,mime)
        except urllib2.HTTPError as e:
            print "[ERR] HTTPError: %s %s" % (url,e.code)
            return (e.code,0,"",0,"")
        except urllib2.URLError as e:
            print "[ERR] URLError: %s %s " % (e.reason.errno,e.reason.strerror)
            return (e.reason.errno,0,e.reason.strerror,0,"")
        except e:
            print "[ERR] UnknownError %s" % url
            return (112,0,e,0,"")
    def socket_available(self,port):
        s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        r=s.connect_ex(('127.0.0.1',port))
        s.close()
        return {'port': port, 'is_used': True if r==0 else False}
    def mem_stat(self):
        if psutil:
            mem = psutil.virtual_memory()
            sw = psutil.swap_memory()
            return [mem.percent,sw.percent]
        else:
            return None
    def db_available(self,db):
        result = {}
        cnxn = False
        cursor = False
        if db.type == 'odbc':
            try:
                cnxn = pyodbc.connect(db.connect)
                cursor = cnxn.cursor()
                cursor.execute(db.query)
                value = cursor.fetchone()[0]
            except:
                result = {'desc': db.name, 'status': STATUS_UNAVAILABLE, 'data': 'E1: Could not connect or execute query'}
            else:
                result = {'desc': db.name, 'status': STATUS_OK, 'data': value}
            finally:
                cursor != False and cursor.close()
                cnxn != False and cnxn.close()
        elif db.type == 'ora':
            try:
                cnxn = cx_Oracle.connect(db.connect)
                cursor = cnxn.cursor()
                cursor.execute(db.query)
                value = cursor.fetchone()[0]
            except:
                result = {'desc': db.name, 'status': STATUS_UNAVAILABLE, 'data': 'E2: Could not connect or execute query'}
            else:
                result = {'desc': db.name, 'status': STATUS_OK, 'data': value}
            finally:
                cursor != False and cursor.close()
                cnxn != False and cnxn.close()
        else:
            result = {'desc': db.name, 'result': False, 'data': 'E2: Unknown driver'}
        return result
    def health_check(self,url):
        (code,time,data,size,mime)=self.resource_available(url)
        data=mime if code==200 else data
        return (code,time,data)
    def local_statistics(self, node):
        
        if isinstance(node, Node):
            return {'status': STATUS_OK,
                'type':       TYPE_REQ,
                'version':    PYMON_VERSION,
                'mounts':     map(self.mount_statistics, node.mounts),
                'loadavg':    self.load_average(),
                'mem':        self.mem_stat(),
                'ports':      map(self.socket_available, node.ports),
                'db':         map(self.db_available, node.dbs),
                'cpu':        last_collector_value}
        else:
            return {'status': STATUS_NODE_NOT_DEFINED, 'type': TYPE_REQ, 'version': PYMON_VERSION}
    def stop_node(self):
        global IS_ENABLED
        print "STOP NODE"
        IS_ENABLED = False
        return True
    def do_GET(self):
        (path, qs) = (urlparse(self.path).path, parse_qs(urlparse(self.path).query))
        # print "Parse: %s <<>> %s" % (path, qs) # qs.__class__.__name__

        try:
            if path.endswith(".js") and SERVE_STATIC == True:
                f = open(PATH_STATIC + path)
                self.send_response(200)
                self.send_header('Content-type', 'text/javascript')
                self.end_headers()
                self.wfile.write(f.read())
                f.close()
                return
            if path.endswith(".css") and SERVE_STATIC == True:
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
            if path == URL_CMD_STOP and qs == {}:
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                for node in NODES:
                    if is_localhost(node.host):
                        self.wfile.write(json.dumps({'status': STATUS_OK, 'type': TYPE_CMD, 'version': PYMON_VERSION, 'command': 'stop'}))
                        self.stop_node()
                        return
                self.wfile.write(json.dumps({'status': STATUS_NODE_NOT_DEFINED, 'type': TYPE_CMD, 'version': PYMON_VERSION, 'command': 'stop'}))
                return
            if path == URL_CMD_STOP:
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                print qs
                
                if 'node' in qs:
                    if isinstance(qs['node'], list) and len(qs['node']) == 1:
                        target = qs['node'][0]
                        if is_localhost(target):
                            self.wfile.write(json.dumps({'status': STATUS_OK, 'type': TYPE_CMD, 'version': PYMON_VERSION, 'command': 'stop'}))
                            self.stop_node()
                        else:
                            (code,time,external_data,size,mime)=self.resource_available("http://%s:%s%s" % (target,HTTP_PORT,URL_CMD_STOP))
                            if code == 200:
                                self.wfile.write(json.dumps(json.loads(external_data)))
                            else:
                                self.wfile.write(json.dumps({'status': STATUS_UNAVAILABLE, 'type': TYPE_CMD, 'command': 'stop'}))
                            return
                else:
                    self.wfile.write(json.dumps({'status': STATUS_CMD_WRONG, 'type': TYPE_CMD, 'version': PYMON_VERSION, 'command': 'stop'}))
                    self.stop_node()
                    return
            if path == URL_CMD_STOP_ALL and qs == {}:
                
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                
                data = []
                
                for node in NODES:
                    if is_localhost(node.host):
                        node_dict={'status': STATUS_OK, 'type': TYPE_CMD, 'version': PYMON_VERSION, 'command': 'stop-all'}
                        self.stop_node()
                    else:
                        (code,time,external_data,size,mime)=self.resource_available("http://%s:%s%s" % (node.host,HTTP_PORT,URL_CMD_STOP))
                        if code == 200:
                            node_dict=json.loads(external_data)
                        else:
                            node_dict={'status': STATUS_UNAVAILABLE, 'type': TYPE_CMD, 'command': 'stop'}
                    node_dict['node']=node.host
                    data.append(node_dict)
                self.wfile.write(json.dumps(data))
                return
            if path == URL_STATISTICS and qs == {}:
                
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                
                data = []
                for node in NODES:
                    if is_localhost(node.host):
                        node_dict=self.local_statistics(node)
                    else:
                        (code,time,external_data,size,mime)=self.resource_available("http://%s:%s%s" % (node.host,HTTP_PORT,URL_NODE_STATISTICS))
                        if code == 200:
                            node_dict=json.loads(external_data)
                        else:
                            node_dict={'status': STATUS_UNAVAILABLE, 'type': TYPE_REQ, 'code': code}
                    node_dict['node']=node.host
                    node_dict['group']=node.group
                    node_dict['desc']=node.desc
                    node_dict['urls']=[]
                    for url in node.urls:
                        (ck_code,ck_time,ck_data)=self.health_check(url.address)
                        node_dict['urls'].append({'code': ck_code, 'time': ck_time, 'data': ck_data, 'desc': url.name})
                    data.append(node_dict)
                self.wfile.write(json.dumps(data))
                return
            if path == URL_NODE_STATISTICS and qs == {}:
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.end_headers()
                for node in NODES:
                    if is_localhost(node.host):
                        self.wfile.write(json.dumps(self.local_statistics(node)))
                        return
                self.wfile.write(json.dumps(self.local_statistics(None)))
                return 
            return
        except IOError:
            self.send_error(404,'File Not Found: %s' % self.path)


def background_collector(mq): ### TODO: refactor
    global last_collector_value
    while True:
        if psutil:
            last_collector_value = psutil.cpu_percent(interval=1.0,percpu=False)
        else:
            cmd = {
                'darwin': "sar 5 1 |tail -1|awk '{print $2}'" # macosx
            }
            default_cmd = "sar 5 1 |tail -1|awk '{print $3}'" # linux2
            
            output=""
            p1 = subprocess.Popen(['sar','5','1'], stdout=subprocess.PIPE)
            p2 = subprocess.Popen(['tail','-1'], stdin=p1.stdout, stdout=subprocess.PIPE)
            p3 = subprocess.Popen(['awk','{print $3}'], stdin=p2.stdout, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            output, err = p3.communicate()
            
            last_collector_value = output.strip()

###def signal_handler(signal, frame):
###        print('TRAP!')
###        os.remove(PATH_PID_FILE) if os.path.isfile(PATH_PID_FILE) else True
###        sys.exit(0)

if __name__ == '__main__':

    ###print "PID: %s" % os.getpid()
    ###with open(PATH_PID_FILE, 'w') as pidfile:
    ###    pidfile.write(str(os.getpid()))
    
    for node in NODES:
        if is_localhost(node.host):

            mq = Queue.Queue() # multi-process queue
            last_collector_value = None # unsafe for many processes
            collector_t = threading.Thread(target=background_collector, args = (mq,))
            collector_t.daemon = True
            collector_t.start()
            
            server = HTTPServer(('', HTTP_PORT), MyHandler)
            print "Starting on port %s" % HTTP_PORT
            try:
                while IS_ENABLED: server.handle_request()
            finally:
                server.server_close()

    ###signal.signal(signal.SIGINT, signal_handler)  # kill -2 <pid> #INT
    #signal.signal(signal.SIGQUIT, signal_handler) # kill -3 <pid>
    #signal.signal(signal.SIGABRT, signal_handler) # kill -6 <pid>
    #signal.signal(signal.SIGTERM, signal_handler) # kill -15 <pid> || kill <pid>
    

    ### server = {}
    ### try:
    ###     server = HTTPServer(('', HTTP_PORT), MyHandler)
    ###     print "Starting on port %s" % HTTP_PORT
    ###     server.serve_forever()
    ### #except KeyboardInterrupt:
    ### #    print '^C received, shutting down server'
    ### #except Exception, e:
    ### #    print 'Exception detected'
    ### finally:
    ###     print 'Exiting'
    ###     os.remove(PATH_PID_FILE) if os.path.isfile(PATH_PID_FILE) else True
    ###     server.socket.close() if server != {} else True
    ###     #os.remove(PATH_PID_FILE) if os.path.isfile(PATH_PID_FILE) else True
    ###     #server.socket.close() # unsafe
