
#
#  Multi::APIDump  -  Regular dumps of the database for public API stuff
#

package Multi::APIDump;

use strict;
use warnings;
use POE;
use JSON::XS;
use PerlIO::gzip;
use Time::HiRes 'time';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw| _start shutdown generate tags_write |],
    ],
    heap => {
      regenerate_interval => 86400, # daily min.
      tagsfile => "$VNDB::ROOT/static/api/tags.json.gz",
      @_,
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('apidump');
  $_[KERNEL]->yield('generate');
  $_[KERNEL]->sig(shutdown => 'shutdown');
}


sub shutdown {
  $_[KERNEL]->delay('generate');
  $_[KERNEL]->alias_remove('apidump');
}


sub generate {
  $_[KERNEL]->alarm(generate => int((time+3)/$_[HEAP]{regenerate_interval}+1)*$_[HEAP]{regenerate_interval});

  # The subqueries are kinda ugly, but it's convenient to have everything in a single query.
  $_[KERNEL]->post(pg => query => q{
    SELECT id, name, description, meta, c_items AS vns, cat,
      (SELECT string_agg(alias,'$$$-$$$') FROM tags_aliases where tag = id) AS aliases,
      (SELECT string_agg(parent::text, ',') FROM tags_parents WHERE tag = id) AS parents
    FROM tags WHERE state = 2
  }, undef, 'tags_write');
}


sub tags_write {
  my($res, $time) = @_[ARG1,ARG3];
  my $ws = time;

  for(@$res) {
    $_->{id} *= 1;
    $_->{meta} = $_->{meta} ? JSON::XS::true : JSON::XS::false;
    $_->{aliases} = [ split /\$\$\$-\$\$\$/, ($_->{aliases}||'') ];
    $_->{parents} = [ map $_*1, split /,/, ($_->{parents}||'') ];
  }

  open my $f, '>:gzip:utf8', "$_[HEAP]{tagsfile}~" or die $!;
  print $f JSON::XS->new->encode($res);
  close $f;
  rename "$_[HEAP]{tagsfile}~", $_[HEAP]{tagsfile} or die $!;

  my $wt = time-$ws;
  $_[KERNEL]->call(core => log => 'Wrote %s in %.2fs query + %.2fs write, size: %.1fkB, tags: %d.',
    $_[HEAP]{tagsfile}, $time, $wt, (-s $_[HEAP]{tagsfile})/1024, scalar @$res);
}

1;
