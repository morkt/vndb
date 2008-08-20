#!/bin/sh

# update_1.22.sql must be executed before this script

cd /www/vndb

# delete all relation graphs (just the files)
find static/rg -name '*.gif' -delete

# delete all relation graph image maps (entire directory)
rm -rf data/rg

# regenerate all relation graphs
util/multi.pl -c 'relgraph all'


