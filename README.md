# populate

Generate pseudorandom file system churn with IO noise. Essentially spin up a ton of 'users' and files to create artificial activities.

# what it is:

A bash script to generate a ton of content and files rapidly, pseudorandomly update it, modify it, move it, copy it, and erase it, with defined limits on how much content there is. Stress test a system, populate a file system, do stuff, generate logs and system events. Use to various ends. 

# how to use it

If you cron it (every minute, perhaps), it'll chug merrily away subject to it's defined limits, and will attempt to only run a single iteration of the program at any given time. Use as a dedicated user (ideally for safety).

# notes

This should work fine to run multiple iterations of it, if you simply name the initiating files differently -- e.g., populate1.sh, populate2.sh, and so on. 

You'll run into I/O, iops, and other sorts of chaos on your system if it's not robust enough to handle multiple instances. 

On a 2013 Macbook Pro test (SSD drive) with Debian 9 in VMWare Fusion with 4GB Ram, and 2 CPU procs, 40GB HDD, and otherwise ultra-vanilla Debian configurations, it was able to run three instances with only moderate load. 

Deletion/culling once at quota is the most impactful on the system. Note: culling 1000~ files at a time is most efficient, doing a single sweep at a time for the 'oldest' files. 

Individual files and directories are cattle and irrelevant as unique entities. 

###
