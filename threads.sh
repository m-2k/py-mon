#!/usr/bin/env python
import Queue
import threading
import urllib2
import os
import time

# # called by each thread
# def get_url(q, url):
#     # q.put(urllib2.urlopen(url).read())
#     q.put(url)
#
# theurls = ["http://google.com", "http://yahoo.com"]
#
# q = Queue.Queue()
#
# for u in theurls:
#     t = threading.Thread(target=get_url, args = (q,u))
#     t.daemon = True
#     t.start()
#
# s = (q.get(),q.get())
# print s

z = 0

# called by each thread
def get_url(q):
    # q.put(urllib2.urlopen(url).read())
    global z
    while True:
        time.sleep(0.1)
        z += 1
        x = q.get() + 100
        q.put(x)

theurls = ["http://google.com", "http://yahoo.com"]

q = Queue.Queue()
q.put(0)


t = threading.Thread(target=get_url, args = (q,))
t.daemon = True
t.start()
# t.join()

time.sleep(2)
# s = q.get()
print q.empty()
print q.get()
print z