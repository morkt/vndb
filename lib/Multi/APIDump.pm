
#
#  Multi::APIDump  -  Regular dumps of the database for public API stuff
#

package Multi::APIDump;

use strict;
use warnings;
use Multi::Core;
use JSON::XS;
use PerlIO::gzip;


sub run {
  push_watcher schedule 0, 24*3600, \&generate;
}


sub tags_gen {
  # The subqueries are kinda ugly, but it's convenient to have everything in a single query.
  pg_cmd q|
    SELECT id, name, description, meta, c_items AS vns, cat,
      (SELECT string_agg(alias,'$$$-$$$') FROM tags_aliases where tag = id) AS aliases,
      (SELECT string_agg(parent::text, ',') FROM tags_parents WHERE tag = id) AS parents
    FROM tags WHERE state = 2
  |, undef, sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1;
    my $ws = AE::time;
    my @res = $res->rowsAsHashes;
    for(@res) {
      $_->{id} *= 1;
      $_->{meta} = $_->{meta} ? JSON::XS::true : JSON::XS::false;
      $_->{vns} *= 1;
      $_->{aliases} = [ split /\$\$\$-\$\$\$/, ($_->{aliases}||'') ];
      $_->{parents} = [ map $_*1, split /,/, ($_->{parents}||'') ];
    }
    writejson(\@res, "$VNDB::ROOT/www/api/tags.json.gz", $time, $ws);
  };
}


sub traits_gen {
  pg_cmd q|
    SELECT id, name, alias AS aliases, description, meta, c_items AS chars,
      (SELECT string_agg(parent::text, ',') FROM traits_parents WHERE trait = id) AS parents
    FROM traits WHERE state = 2
  |, undef, sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1;
    my $ws = AE::time;
    my @res = $res->rowsAsHashes;
    for(@res) {
      $_->{id} *= 1;
      $_->{meta} = $_->{meta} ? JSON::XS::true : JSON::XS::false;
      $_->{chars} *= 1;
      $_->{aliases} = [ split /\r?\n/, ($_->{aliases}||'') ];
      $_->{parents} = [ map $_*1, split /,/, ($_->{parents}||'') ];
    }
    writejson(\@res, "$VNDB::ROOT/www/api/traits.json.gz", $time, $ws);
  };
}


sub writejson {
  my($data, $file, $sqltime, $procstart) = @_;

  open my $f, '>:gzip:utf8', "$file~" or die "Writing $file: $!";
  print $f JSON::XS->new->encode($data);
  close $f;
  rename "$file~", $file or die "Renaming $file: $!";

  my $wt = AE::time-$procstart;
  AE::log info => sprintf 'Wrote %s in %.2fs query + %.2fs write, size: %.1fkB, items: %d.',
    $file, $sqltime, $wt, (-s $file)/1024, scalar @$data;
}


sub votes_gen {
  pg_cmd q{
    SELECT vv.vid||' '||vv.uid||' '||vv.vote as l
      FROM votes vv
      JOIN users u ON u.id = vv.uid
      JOIN vn v ON v.id = vv.vid
     WHERE NOT v.hidden
       AND NOT u.ign_votes
       AND NOT EXISTS(SELECT 1 FROM users_prefs up WHERE up.uid = u.id AND key = 'hide_list')
  }, undef, sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1;
    my $ws = AE::time;

    my $file = "$VNDB::ROOT/www/api/votes.gz";
    open my $f, '>:gzip:utf8', "$file~" or die "Writing $file: $!";
    printf $f "%s\n", $res->value($_,0) for (0 .. $res->rows-1);
    close $f;
    rename "$file~", $file or die "Renaming $file: $!";

    my $wt = AE::time-$ws;
    AE::log info => sprintf 'Wrote %s in %.2fs query + %.2fs write, size: %.1fkB, items: %d.',
      $file, $time, $wt, (-s $file)/1024, scalar $res->rows;
  };
}


sub generate {
  # TODO: Running these functions in the main process adds ~11MB of RAM because
  # the full query results are kept in memory. It might be worthwile to
  # generate the dumps in a forked process.
  tags_gen;
  my $a; $a = AE::timer  5, 0, sub { traits_gen; undef $a; };
  my $b; $b = AE::timer 10, 0, sub { votes_gen; undef $b; };
}

1;
