# all (default)
#   Same as `make dirs js icons skins robots`
#
# dirs
#   Creates the required directories not present in git
#
# js
#   Generates the Javascript code
#
# icons
#   Generates the CSS icon sprites
#
# skins
#   Generates the CSS code
#
# robots
#   Ensures that www/robots.txt and static/robots.txt exist. Can be modified to
#   suit your needs.
#
# chmod
#   For when the http process is run from a different user than the files are
#   chown'ed to. chmods all files and directories written to from vndb.pl.
#
# chmod-autoupdate
#   As chmod, but also chmods all files that may need to be updated from a
#   normal 'make' run. Should be used when the regen_static option is enabled
#   and the http process is run from a different user.
#
# multi-start, multi-stop, multi-restart:
#   Start/stop/restart the Multi daemon. Provided for convenience, a proper initscript
#   probably makes more sense.
#
# sql-import
#   Imports util/sql/all.sql into your (presumably empty) database
#
# update-<version>
#   Updates all non-versioned items from the version before to <version>.
#
# NOTE: This Makefile has only been tested using a recent version of GNU make
#   in a relatively up-to-date Arch/Gentoo Linux environment, and may not work in
#   other environments. Patches to improve the portability are always welcome.


.PHONY: all dirs js icons skins robots chmod multi-stop multi-start multi-restart sql-import\
	update-2.10 update-2.11 update-2.12 update-2.13 update-2.14 update-2.15 update-2.16 update-2.17\
	update-2.18 update-2.19 update-2.20 update-2.21 update-2.22 update-2.23

all: dirs js skins robots data/config.pl util/sql/editfunc.sql

dirs: static/ch static/cv static/sf static/st data/log www www/feeds www/api

js: static/f/vndb.js

icons: data/icons/icons.css

skins: $(shell ls static/s | sed -e 's/\(.\+\)/static\/s\/\1\/style.css/g')

robots: dirs www/robots.txt static/robots.txt

util/sql/editfunc.sql: util/sqleditfunc.pl util/sql/schema.sql
	util/sqleditfunc.pl

static/ch static/cv static/sf static/st:
	mkdir $@;
	for i in $$(seq -w 0 1 99); do mkdir "$@/$$i"; done

data/log www www/feeds www/api:
	mkdir $@

static/f/vndb.js: data/js/*.js util/jsgen.pl data/config.pl data/global.pl
	util/jsgen.pl

data/icons/icons.css: data/icons/*.png data/icons/*/*.png util/spritegen.pl
	util/spritegen.pl

static/s/%/style.css: static/s/%/conf util/skingen.pl data/style.css data/icons/icons.css
	util/skingen.pl $*

%/robots.txt:
	echo 'User-agent: *' > $@
	echo 'Disallow: /' >> $@

chmod: all
	chmod -R a-x+rwX static/{ch,cv,sf,st}

chmod-autoupdate: chmod
	chmod a+xrw static/f data/icons
	chmod -f a-x+rw static/s/*/{style.css,boxbg.png} static/f/icons.png


# may wait indefinitely, ^C and kill -9 in that case
define multi-stop
	if [ -s data/multi.pid ]; then\
	  kill `cat data/multi.pid`;\
	  while [ -s data/multi.pid ]; do\
	    if kill -0 `cat data/multi.pid`; then sleep 1;\
	    else rm -f data/multi.pid; fi\
	  done;\
	fi
endef

define multi-start
	util/multi.pl
endef

multi-stop:
	$(multi-stop)

multi-start:
	$(multi-start)

multi-restart:
	$(multi-stop)
	$(multi-start)


# Small perl script that tries to connect to the PostgreSQL database using 'psql', with the
# connection settings from data/config.pl. May not work in all configurations, though...
define runpsql
	@perl -MDBI -e 'package VNDB;\
	$$ROOT=".";\
	require "data/global.pl";\
	$$_=(DBI->parse_dsn($$VNDB::O{db_login}[0]))[4];\
	$$ENV{PGPASSWORD} = $$VNDB::O{db_login}[2];\
	$$ENV{PGUSER}     = $$VNDB::O{db_login}[1];\
	$$ENV{PGDATABASE} = $$2 if /(dbname|db|database)=([^;]+)/;\
	$$ENV{PGHOST}     = $$1 if /host=([^;]+)/;\
	$$ENV{PGHOSTADDR} = $$1 if /hostaddr=([^;]+)/;\
	$$ENV{PGPORT}     = $$1 if /port=([^;]+)/;\
	$$ENV{PGSERVICE}  = $$1 if /service=([^;]+)/;\
	$$ENV{PGSSLMODE}  = $$1 if /sslmode=([^;]+)/;\
	open F, "|psql" or die $$!;\
	print F while(<>);\
	close F or exit 1'
endef


sql-import: util/sql/editfunc.sql
	${runpsql} < util/sql/all.sql


update-2.10: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.10.sql
	$(multi-start)

update-2.11: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.11.sql
	$(multi-start)

update-2.12: all
	$(multi-stop)
	rm www/sitemap.xml.gz
	${runpsql} < util/updates/update_2.12.sql
	$(multi-start)

update-2.13: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.13.sql
	$(multi-start)

update-2.14: all
	rm -f static/f/script.js
	$(multi-stop)
	${runpsql} < util/updates/update_2.14.sql
	$(multi-start)

update-2.15: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.15.sql
	$(multi-start)

update-2.16: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.16.sql
	$(multi-start)

update-2.17: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.17.sql
	$(multi-start)

update-2.18: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.18.sql
	$(multi-start)

update-2.19: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.19.sql
	$(multi-start)

update-2.20: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.20.sql
	$(multi-start)

update-2.21: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.21.sql
	$(multi-start)

update-2.22: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.22.sql
	$(multi-start)

update-2.23: all
	$(multi-stop)
	${runpsql} < util/updates/update_2.23.sql
	$(multi-start)
