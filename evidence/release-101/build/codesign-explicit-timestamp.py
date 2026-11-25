#!/usr/bin/python3
import os,sys
a=["--timestamp=http://timestamp.apple.com/ts01" if x=="--timestamp" else x for x in sys.argv[1:]]
os.execv("/usr/bin/codesign",["/usr/bin/codesign"]+a)
