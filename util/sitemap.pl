#!/usr/bin/perl

my $sitemapfile = '/www/vndb/www/sitemap.xml.gz';
my $baseurl = 'http://vndb.org';
my %chfr = qw( a always   h hourly  d daily  w weekly  m monthly  y yearly  n never );


# the code
use strict;
use warnings;
use DBI;
use POSIX; # for ceil();
use XML::Writer;
use PerlIO::gzip;
use DateTime;

my $sql = DBI->connect('dbi:Pg:dbname=vndb', 'vndb', 'passwd',
    { RaiseError => 1, PrintError => 0, AutoCommit => 1, pg_enable_utf8 => 1 });

my $urls = 0;
my $x;

sitemap();

sub sitemap {
  print "Creating sitemap...\n";
 # open file and start writing
  open(my $IO, '>:gzip', $sitemapfile) || die $1;
  $x = new XML::Writer(OUTPUT => $IO, ENCODING => 'UTF-8', DATA_MODE => 1, DATA_INDENT => 1);
  $x->xmlDecl();
  $x->comment(q|NOTE: All URL's that require you to login or that may contain usernames are left out.|);
  $x->startTag('urlset', xmlns => 'http://www.sitemaps.org/schemas/sitemap/0.9');

 # some default pages
  _sm_add(@$_) foreach (
    [ '/', 'd' ],
    [ '/faq', 'm' ],
  );

 # some browse pages
  _sm_add('/v/'.$_, 'w') for ('a'..'z', 'all', 'cat');
  _sm_add('/p/'.$_, 'w') for ('a'..'z', 'all');

 # visual novels
  my $q = $sql->prepare(q|
    SELECT v.id, c.added, v.rgraph
    FROM vn v
    JOIN vn_rev vr ON vr.id = v.latest
    JOIN changes c ON vr.id = c.id
  |); $q->execute;
  while($_ = $q->fetchrow_arrayref) {
    _sm_add('/v'.$_->[0], 'w', $_->[1], 0.7);
#    _sm_add('/v'.$_->[0].'/stats', 'w');
    _sm_add('/v'.$_->[0].'/rg', 'w', $_->[1]) if $_->[2];
  }

 # producers
  $q = $sql->prepare(q|
    SELECT p.id, c.added
    FROM producers p
    JOIN producers_rev pr ON pr.id = p.latest
    JOIN changes c ON c.id = pr.id
  |); $q->execute;
  _sm_add('/p'.$_->[0], 'w', $_->[1]) while $_ = $q->fetchrow_arrayref;

 # releases
  $q = $sql->prepare(q|
    SELECT r.id, c.added
    FROM releases r
    JOIN releases_rev rr ON rr.id = r.latest
    JOIN changes c ON c.id = rr.id
  |); $q->execute;
  _sm_add('/r'.$_->[0], 'w', $_->[1], 0.3) while $_ = $q->fetchrow_arrayref;


 # and stop writing
  $x->endTag('urlset');
  $x->end();
  close($IO);
  printf "Sitemap created, %d urls added\n", $urls;
}



sub _sm_add {
  my($loc, $cf, $lastmod, $pri) = @_;
  $x->startTag('url');
   $x->dataElement('loc', $baseurl . $loc);
   $x->dataElement('changefreq', $chfr{$cf}?$chfr{$cf}:$cf) if defined $cf;
   $x->dataElement('lastmod', DateTime->from_epoch(epoch => $lastmod)->ymd) if defined $lastmod;
   $x->dataElement('priority', $pri) if defined $pri;
  $x->endTag('url');
  $urls++;
}
