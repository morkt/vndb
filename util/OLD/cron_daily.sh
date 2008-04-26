#!/bin/bash

# we want to run as user 'yorhel'
if [ `id -nu` != 'yorhel' ]; then
  su yorhel -c "$0"
  exit;
fi

cd /www/vndb/util

SQL='psql -e vndb -U vndb';

echo '

   =================================================================================
=================== VNDB cron running at '`date`' ==================
=== Executing SQL statements'
echo '\timing
\i cron_daily.sql' | $SQL

echo '=== Creating/updating sitemap';
./sitemap.pl
#echo '=== Cleaning up images';
#./cleanimg.pl
#echo '=== Creating relation graphs';
#./relgraph.pl
echo '=== VACUUM FULL ANALYZE';
vacuumdb -U yorhel --full --analyze vndb  >/dev/null 2>&1

echo '=== VNDB cron finished at '`date`' ===';

