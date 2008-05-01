
#
#  Multi::Sitemap  -  The sitemap generator
#

package Multi::Sitemap;

use strict;
use warnings;
use POE;
use XML::Writer;
use PerlIO::gzip;
use DateTime;


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start cmd_sitemap staticpages vnpages releasepages producerpages finish addurl |],
    ],
    heap => {
      output => '/www/vndb/www/sitemap.xml.gz',
      baseurl => 'http://vndb.org',
      @_,
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('sitemap');
  $_[KERNEL]->call(core => register => qr/^sitemap$/, 'cmd_sitemap');
  
 # Regenerate the sitemap every day on 0:00
  $_[KERNEL]->post(core => addcron => '0 0 * * *', 'sitemap');
}


sub cmd_sitemap {
  # Function order:
  #  cmd_sitemap
  #  staticpages
  #  vnpages
  #  releasepages
  #  producerpages
  #  finish

  $_[HEAP]{cmd} = $_[ARG0];
  $_[HEAP]{urls} = 0;

  open($_[HEAP]{io}, '>:gzip', $_[HEAP]{output}) || die $1;
  $_[HEAP]{xml} = new XML::Writer(
    OUTPUT => $_[HEAP]{io},
    ENCODING => 'UTF-8',
    DATA_MODE => 1,
    DATA_INDENT => 1
  );
  $_[HEAP]{xml}->xmlDecl();
  $_[HEAP]{xml}->comment(q|NOTE: All URL's that require you to login or that may contain usernames are left out.|);
  $_[HEAP]{xml}->startTag('urlset', xmlns => 'http://www.sitemaps.org/schemas/sitemap/0.9');

  $_[KERNEL]->yield('staticpages');
}


sub staticpages {
  $_[KERNEL]->call(core => log => 3, 'Adding static pages');

  $_[KERNEL]->call(sitemap => addurl => '', 'd');
  $_[KERNEL]->call(sitemap => addurl => 'faq', 'm');

  $_[KERNEL]->call(sitemap => addurl => $_, 'w')
    for ( (map { 'v/'.$_ } 'a'..'z'), 'v/all', 'v/cat', (map { 'p/'.$_ } 'a'..'z'), 'p/all');

  $_[KERNEL]->yield('vnpages');
}


sub vnpages {
  $_[KERNEL]->call(core => log => 3, 'Adding visual novel pages');

  my $q = $Multi::SQL->prepare(q|
    SELECT v.id, c.added, v.rgraph
    FROM vn v
    JOIN vn_rev vr ON vr.id = v.latest
    JOIN changes c ON vr.id = c.id
  |);
  $q->execute;
  while(local $_ = $q->fetchrow_arrayref) {
    $_[KERNEL]->call(sitemap => addurl => 'v'.$_->[0], 'w', $_->[1], 0.7);
    $_[KERNEL]->call(sitemap => addurl => 'v'.$_->[0].'/rg', 'w', $_->[1], 0.7) if $_->[2];
  }

  $_[KERNEL]->yield('releasepages');
}


sub releasepages {
  $_[KERNEL]->call(core => log => 3, 'Adding release pages');

  my $q = $Multi::SQL->prepare(q|
    SELECT r.id, c.added
    FROM releases r
    JOIN releases_rev rr ON rr.id = r.latest
    JOIN changes c ON c.id = rr.id
  |);
  $q->execute;
  while(local $_ = $q->fetchrow_arrayref) {
    $_[KERNEL]->call(sitemap => addurl => 'r'.$_->[0], 'w', $_->[1], 0.3);
  }

  $_[KERNEL]->yield('producerpages');
}


sub producerpages {
  $_[KERNEL]->call(core => log => 3, 'Adding producer pages');
  
  my $q = $Multi::SQL->prepare(q|
    SELECT p.id, c.added
    FROM producers p
    JOIN producers_rev pr ON pr.id = p.latest
    JOIN changes c ON c.id = pr.id
  |); 
  $q->execute;
  while(local $_ = $q->fetchrow_arrayref) {
    $_[KERNEL]->call(sitemap => addurl => 'p'.$_->[0], 'w', $_->[1]);
  }

  $_[KERNEL]->yield('finish');
}


sub finish {
  $_[HEAP]{xml}->endTag('urlset');
  $_[HEAP]{xml}->end();
  close $_[HEAP]{io};
  $_[KERNEL]->call(core => log => 2 => 'Wrote %d URLs in the sitemap', $_[HEAP]{urls});
  $_[KERNEL]->post(core => finish => $_[HEAP]{cmd});
  delete @{$_[HEAP]}{qw| xml io cmd urls |};
}


sub addurl { # loc, changefreq, lastmod, priority
  $_[HEAP]{xml}->startTag('url');
   $_[HEAP]{xml}->dataElement(loc => $_[HEAP]{baseurl}.'/'.$_[ARG0]);
   $_[HEAP]{xml}->dataElement(changefreq => $_[ARG1]) if defined $_[ARG1];
   $_[HEAP]{xml}->dataElement(lastmod => DateTime->from_epoch(epoch => $_[ARG2])->ymd) if defined $_[ARG2];
   $_[HEAP]{xml}->dataElement(priority => $_[ARG3]) if defined $_[ARG3];
  $_[HEAP]{xml}->endTag('url');
  $_[HEAP]{urls}++;
}


1;


