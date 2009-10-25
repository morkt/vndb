# all (default)
#   Same as $ make staticdirs js skins www robots
#
# staticdirs
# 	Creates the required directory structures in static/
#
# js
# 	Generates the Javascript code
#
# skins
# 	Generates the CSS code
#
# robots
# 	Ensures that www/robots.txt and static/robots.txt exist. Can be modified to
# 	suit your needs.
#
# chmod
# 	For when the http process is run from a different user than the files are
# 	chown'ed to. chmods all files and directories written to from vndb.pl.
# 	(including the stylesheets and javascript code, so these can be auto-updated)
#
# chmod-tladmin
# 	The TransAdmin plugin also needs write access to some files
#
#
# NOTE: This Makefile has only been tested using a recent version of GNU make
#   in a relatively up-to-date Arch Linux environment, and may not work in other
#   environments. Patches to improve the portability are always welcome.


.PHONY: all staticdirs js skins robots chmod chmod-tladmin

all: staticdirs js skins robots


staticdirs: static/cv static/sf static/st

static/cv static/sf static/st:
	mkdir $@;
	for i in $$(seq -w 0 1 99); do mkdir "$@/$$i"; done


js: static/f/script.js

static/f/script.js: data/script.js data/lang.txt util/jsgen.pl
	util/jsgen.pl


skins: static/s/*/style.css

static/s/%/style.css: static/s/%/conf util/skingen.pl data/style.css
	util/skingen.pl $*


www:
	mkdir www

robots: www www/robots.txt static/robots.txt

%/robots.txt:
	echo 'User-agent: *' > $@
	echo 'Disallow: /' >> $@


chmod: all
	chmod a-x+rw static/f/script.js
	chmod -R a-x+rwX static/{cv,sf,st}
	chmod a-x+rw static/s/*/{style.css,boxbg.png}

chmod-tladmin:
	chmod a-x+rwX data/lang.txt data/docs data/docs/*\.*

