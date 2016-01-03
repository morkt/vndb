package VNDB;

# This file is used to override config options in global.pl.
# You can override anything you want.

%O = (
  %O,
  db_login      => [ 'dbi:Pg:dbname=<database>', '<user>', '<password>' ],
  logfile       => $ROOT.'/err.log',
  xml_pretty    => 0,
  log_queries   => 0,
  debug         => 1,
  cookie_defaults => { path => '/' },
);

%S = (
  %S,
  url          => 'http://your.site.root/',
  url_static   => 'http://your.static.site.root/',
  form_salt    => '<some unique string>',
  scrypt_salt  => '<another unique string>',
);


# Uncomment to enable certain features of Multi

#$M{modules}{API} = {};
#$M{modules}{APIDump} = {};

#$M{modules}{IRC} = {
#  nick    => 'MyVNDBBot',
#  server  => 'irc.synirc.net',
#  channels => [ '#vndb' ],
#  pass    => '<nickserv-password>',
#  masters => [ 'yorhel!~Ayo@your.hell' ],
#};


# Uncomment the compression method to use for the generated Javascript (or just leave as-is to disable compression)
#$JSGEN{compress} = 'JavaScript::Minifier::XS';
#$JSGEN{compress} = "|/usr/bin/uglifyjs --compress --mangle";

# Uncomment to create pre-compressed css and js files using zopfli
#$JSGEN{gzip} = $SKINGEN{gzip} = "/usr/bin/zopfli";

# Uncomment to generate an extra small icons.png
# (note: using zopflipng or pngcrush with the slow option is *really* slow, but compresses awesomely)
#$SPRITEGEN{crush} = '/usr/bin/pngcrush -q';
#$SPRITEGEN{crush} = '/usr/bin/zopflipng -m --lossy_transparent';
#$SPRITEGEN{slow} = 1;
