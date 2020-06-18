# Alan Baines

import os.path
import os
import threading
import hashlib
import shutil
import time
import glob
import re
import zipfile
import datetime
import tempfile
import sys
import traceback
import json

def get_mod_name():
   with open('info.json') as info_json:
      data = json.load(info_json)
      name = data['name']
      version = data['version']
      n_v = name+'_'+version
      return n_v

rootx = os.path.dirname(os.path.abspath(__file__))
print( 'rootx', rootx )

baseFolder = rootx[:rootx.rindex(os.sep)+1]
print( 'baseFolder', baseFolder )

rootName = get_mod_name()
print( 'rootName', rootName )

zipPath = os.path.join(baseFolder,rootName+".zip")
print( 'zipPath', zipPath )

if os.path.exists(zipPath):
   os.remove(zipPath)
   print("Zip Removed:",zipPath)


whitelistextensions=[
".cfg",
".lua",
]

whitelist=[
os.sep+"README.md",
os.sep+"changelog.txt",
os.sep+"info.json",
os.sep+"license.md",
os.sep+"thumbnail.png",
os.sep+"description.json",
]

whitelistextensionsinsidefolders=[
".png",
".ogg",
]



def getAllFiles(directory):
   returns = []
   for path, subdirs, files in os.walk(directory):
      for name in files:
         f = os.path.join(path, name)
         returns.append(f)
   return returns

def endsWithAny(text,collection):
   for c in collection:
      if text.endswith(c):
         return c
   return False

git_directory_flag = os.sep+'.git'+os.sep

def collectWhiteListFiles(root,whitelist,whitelistextensions,whitelistextensionsinsidefolders):
   returns = []
   ignored = []

   for file in getAllFiles(root):
      shortname = file[len(root):]
      c = shortname.count(os.sep)
      if endsWithAny(file,whitelist):
         returns.append(shortname)
      elif endsWithAny(file,whitelistextensions):
         returns.append(shortname)
      elif c >= 2 and endsWithAny(file,whitelistextensionsinsidefolders):
         returns.append(shortname)
      elif git_directory_flag in file:
         pass
      else:
         ignored.append(shortname)

   return returns, ignored


def setExtensions(listFiles):
   s = set()
   for f in listFiles:
      e = f[f.rindex('.')+1:]
      s.add(e)
   return s

def printWhiteListFiles(root):
   print("")
   print('printWhiteListFiles','root',root)
   r,i = collectWhiteListFiles(root,whitelist,whitelistextensions,whitelistextensionsinsidefolders)

   if len(i)>0:
      print ('{:-^80}'.format(' ignored '))
      for f in i:
         print(f)
      print(setExtensions(i))

   print ('{:=^80}'.format(' white '))
   for f in r:
      print(f)
   print(setExtensions(r))
   print("")


printWhiteListFiles(rootx)


print ('{:+^80}'.format(' zip '))
r,i = collectWhiteListFiles(rootx,whitelist,whitelistextensions,whitelistextensionsinsidefolders)
with zipfile.ZipFile(zipPath, 'w') as zout:
   for f in r:
      arcname=rootName+f
      filename="."+f
      print(filename,arcname)
      zout.write(filename,arcname)


# check os.name to determine interactive mode
if os.name == 'nt':
   input("Press Enter to continue...")
elif os.name == 'posix':
   print( os.listdir(os.pardir) )
else:
   raise Exception("unknown os.name",os.name)

