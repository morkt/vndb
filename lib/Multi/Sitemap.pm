
#
#  Multi::Sitemap  -  The sitemap generator
#

package Multi::Sitemap;

use strict;
use warnings;
use POE;
use XML::Writer;
use PerlIO::gzip;
use POSIX 'strftime';
use Time::HiRes 'gettimeofday', 'tv_interval';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start shutdown check_age generate addquery addurl finish |],
    ],
    heap => {
      output => $VNDB::ROOT.'/www/sitemap.xml.gz',
      max_age =>  24*3600, # seconds
      check_delay => 3600, # seconds
      @_,
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('sitemap');
  $_[KERNEL]->yield('check_age');
  $_[KERNEL]->sig(shutdown => 'shutdown');
}


sub shutdown {
  $_[KERNEL]->delay('check_age');
  $_[KERNEL]->alias_remove('sitemap');
}


sub check_age {
  # check the last modified time of the sitemap, and if it's older than max_age, regenerate it
  $_[KERNEL]->yield('generate') if !-f $_[HEAP]{output} || (stat $_[HEAP]{output})[9] < time-$_[HEAP]{max_age};

  # check sitemap again later
  $_[KERNEL]->delay(check_age => $_[HEAP]{check_delay});
}


sub generate {
  $_[KERNEL]->call(core => log => '(Re)generating sitemap');

  $_[HEAP]{urls} = 0;
  $_[HEAP]{start} = [ gettimeofday ];

  open($_[HEAP]{io}, '>:gzip', $_[HEAP]{output}) || die $1;
  $_[HEAP]{xml} = new XML::Writer(
    OUTPUT => $_[HEAP]{io},
    ENCODING => 'UTF-8',
    DATA_MODE => 1,
    DATA_INDENT => 1
  );
  $_[HEAP]{xml}->xmlDecl();
  $_[HEAP]{xml}->startTag('urlset', xmlns => 'http://www.sitemaps.org/schemas/sitemap/0.9');

  # /
  $_[KERNEL]->call(sitemap => addurl => '', 'daily');

  # /d+
  /([0-9]+)$/ && $_[KERNEL]->call(sitemap => addurl => 'd'.$1, 'monthly', [stat $_]->[9])
    for (glob "$VNDB::ROOT/data/docs/*");

  # /v/[browse] & /p/[browse]
  $_[KERNEL]->call(sitemap => addurl => $_, 'weekly')
    for (map { 'v/'.$_, 'p/'.$_ } 'a'..'z', 0, 'all');

  # /v+
  $_[KERNEL]->post(pg => query => '
    SELECT v.id, c.added
      FROM vn v
      JOIN vn_rev vr ON vr.id = v.latest
      JOIN changes c ON vr.id = c.id
      WHERE v.hidden = FALSE
      ORDER BY v.id',
    undef, 'addquery', [ 'v', 0.7 ]);

  # /r+
  $_[KERNEL]->post(pg => query => '
    SELECT r.id, c.added
      FROM releases r
      JOIN releases_rev rr ON rr.id = r.latest
      JOIN changes c ON c.id = rr.id
      WHERE r.hidden = FALSE
      ORDER BY r.id',
    undef, 'addquery', [ 'r', 0.5 ]);

  # /p+
  $_[KERNEL]->post(pg => query => '
    SELECT p.id, c.added
      FROM producers p
      JOIN producers_rev pr ON pr.id = p.latest
      JOIN changes c ON c.id = pr.id
      WHERE p.hidden = FALSE
      ORDER BY p.id',
    undef, 'addquery', [ 'p', 0.3 ]);

  # /g+
  $_[KERNEL]->post(pg => query => '
    SELECT t.id, t.added
      FROM tags t
      WHERE state = 2
      ORDER BY t.id',
    undef, 'addquery', [ 'g', 0.3, 1 ]);
}


sub addquery { # num, db-res, [ type, priority, finish ]
  $_[KERNEL]->call(sitemap => addurl => $_[ARG2][0].$_->{id}, 'weekly', $_->{added}, $_[ARG2][1])
    for(@{$_[ARG1]});
  $_[KERNEL]->yield('finish') if $_[ARG2][2];
}


sub finish {
  $_[HEAP]{xml}->endTag('urlset');
  $_[HEAP]{xml}->end();
  close $_[HEAP]{io};

  $_[KERNEL]->call(core => log => 'Wrote %d URLs (%.1f kB gzipped) to the sitemap in %.2f seconds',
    $_[HEAP]{urls}, (-s $_[HEAP]{output})/1024, tv_interval($_[HEAP]{start}));

  delete @{$_[HEAP]}{qw| xml io start urls |};
}


sub addurl { # loc, changefreq, lastmod, priority
  $_[HEAP]{xml}->startTag('url');
   $_[HEAP]{xml}->dataElement(loc => $VNDB::S{url}.'/'.$_[ARG0]);
   $_[HEAP]{xml}->dataElement(changefreq => $_[ARG1]) if defined $_[ARG1];
   $_[HEAP]{xml}->dataElement(lastmod => strftime('%Y-%m-%d', gmtime $_[ARG2])) if defined $_[ARG2];
   $_[HEAP]{xml}->dataElement(priority => $_[ARG3]) if defined $_[ARG3];
  $_[HEAP]{xml}->endTag('url');
  $_[HEAP]{urls}++;
}


1;


