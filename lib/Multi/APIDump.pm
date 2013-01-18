
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
      $p => [qw| _start shutdown tags_gen tags_write traits_gen traits_write writejson|],
    ],
    heap => {
      regenerate_interval => 86400, # daily min.
      tagsfile   => "$VNDB::ROOT/www/api/tags.json.gz",
      traitsfile => "$VNDB::ROOT/www/api/traits.json.gz",
      @_,
    },
  );
}


sub _start {
  $_[KERNEL]->alias_set('apidump');
  $_[KERNEL]->yield('tags_gen');
  $_[KERNEL]->delay(traits_gen => 10);
  $_[KERNEL]->sig(shutdown => 'shutdown');
}


sub shutdown {
  $_[KERNEL]->delay('tags_gen');
  $_[KERNEL]->delay('traits_gen');
  $_[KERNEL]->alias_remove('apidump');
}


sub tags_gen {
  $_[KERNEL]->alarm(tags_gen => int((time+3)/$_[HEAP]{regenerate_interval}+1)*$_[HEAP]{regenerate_interval});

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
    $_->{vns} *= 1;
    $_->{aliases} = [ split /\$\$\$-\$\$\$/, ($_->{aliases}||'') ];
    $_->{parents} = [ map $_*1, split /,/, ($_->{parents}||'') ];
  }

  $_[KERNEL]->yield(writejson => $res, $_[HEAP]{tagsfile}, $time, $ws);
}


sub traits_gen {
  $_[KERNEL]->alarm(traits_gen => int((time+3)/$_[HEAP]{regenerate_interval}+1)*$_[HEAP]{regenerate_interval});

  $_[KERNEL]->post(pg => query => q{
    SELECT id, name, alias AS aliases, description, meta, c_items AS chars,
      (SELECT string_agg(parent::text, ',') FROM traits_parents WHERE trait = id) AS parents
    FROM traits WHERE state = 2
  }, undef, 'traits_write');
}


sub traits_write {
  my($res, $time) = @_[ARG1,ARG3];
  my $ws = time;

  for(@$res) {
    $_->{id} *= 1;
    $_->{meta} = $_->{meta} ? JSON::XS::true : JSON::XS::false;
    $_->{chars} *= 1;
    $_->{aliases} = [ split /\r?\n/, ($_->{aliases}||'') ];
    $_->{parents} = [ map $_*1, split /,/, ($_->{parents}||'') ];
  }

  $_[KERNEL]->yield(writejson => $res, $_[HEAP]{traitsfile}, $time, $ws);
}


sub writejson {
  my($data, $file, $sqltime, $procstart) = @_[ARG0..$#_];

  open my $f, '>:gzip:utf8', "$file~" or die "Writing $file: $!";
  print $f JSON::XS->new->encode($data);
  close $f;
  rename "$file~", $file or die "Renaming $file: $!";

  my $wt = time-$procstart;
  $_[KERNEL]->call(core => log => 'Wrote %s in %.2fs query + %.2fs write, size: %.1fkB, items: %d.',
    $file, $sqltime, $wt, (-s $file)/1024, scalar @$data);
}

1;
