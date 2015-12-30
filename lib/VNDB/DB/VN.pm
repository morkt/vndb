
package VNDB::DB::VN;

use strict;
use warnings;
use TUWF 'sqlprint';
use Exporter 'import';
use VNDB::Func 'gtintype', 'normalize_query';
use Encode 'decode_utf8';

our @EXPORT = qw|dbVNGet dbVNGetRev dbVNRevisionInsert dbVNImageId dbScreenshotAdd dbScreenshotGet dbScreenshotRandom dbVNImportSeiyuu|;


# Options: id, char, search, length, lang, olang, plat, tag_inc, tag_exc, tagspoil,
#   hasani, hasshot, ul_notblack, ul_onwish, results, page, what, sort, reverse, inc_hidden, release
# What: extended anime staff seiyuu relations screenshots relgraph rating ranking wishlist vnlist
#  Note: wishlist and vnlist are ignored (no db search) unless a user is logged in
# Sort: id rel pop rating title tagscore rand
sub dbVNGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page}    ||= 1;
  $o{what}    ||= '';
  $o{sort}    ||= 'title';
  $o{tagspoil} //= 2;

  # user input that is literally added to the query should be checked...
  die "Invalid input for tagspoil or tag_inc at dbVNGet()\n" if
    grep !defined($_) || $_!~/^\d+$/, $o{tagspoil},
      !$o{tag_inc} ? () : (ref($o{tag_inc}) ? @{$o{tag_inc}} : $o{tag_inc});

  my $uid = $self->authInfo->{id};

  my @where = (
    $o{id} ? (
      'v.id IN(!l)' => [ ref $o{id} ? $o{id} : [$o{id}] ] ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(v.title, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(v.title) < 97 OR ASCII(v.title) > 122) AND (ASCII(v.title) < 65 OR ASCII(v.title) > 90)' => 1 ) : (),
    defined $o{length} ? (
      'v.length IN(!l)' => [ ref $o{length} ? $o{length} : [$o{length}] ]) : (),
    $o{lang} ? (
      'v.c_languages && ARRAY[!l]::language[]' => [ ref $o{lang} ? $o{lang} : [$o{lang}] ]) : (),
    $o{olang} ? (
      'v.c_olang && ARRAY[!l]::language[]' => [ ref $o{olang} ? $o{olang} : [$o{olang}] ]) : (),
    $o{plat} ? (
      'v.c_platforms && ARRAY[!l]::platform[]' => [ ref $o{plat} ? $o{plat} : [$o{plat}] ]) : (),
    defined $o{hasani} ? (
      '!sEXISTS(SELECT 1 FROM vn_anime va WHERE va.id = v.id)' => [ $o{hasani} ? '' : 'NOT ' ]) : (),
    defined $o{hasshot} ? (
      '!sEXISTS(SELECT 1 FROM vn_screenshots vs WHERE vs.id = v.id)' => [ $o{hasshot} ? '' : 'NOT ' ]) : (),
    $o{tag_inc} ? (
      'v.id IN(SELECT vid FROM tags_vn_inherit WHERE tag IN(!l) AND spoiler <= ? GROUP BY vid HAVING COUNT(tag) = ?)',
      [ ref $o{tag_inc} ? $o{tag_inc} : [$o{tag_inc}], $o{tagspoil}, ref $o{tag_inc} ? $#{$o{tag_inc}}+1 : 1 ]) : (),
    $o{tag_exc} ? (
      'v.id NOT IN(SELECT vid FROM tags_vn_inherit WHERE tag IN(!l))' => [ ref $o{tag_exc} ? $o{tag_exc} : [$o{tag_exc}] ] ) : (),
    $o{search} ? (
      map +('v.c_search like ?', "%$_%"), normalize_query($o{search})) : (),
    $uid && $o{ul_notblack} ? (
      'v.id NOT IN(SELECT vid FROM wlists WHERE uid = ? AND wstat = 3)' => $uid ) : (),
    $uid && defined $o{ul_onwish} ? (
      'v.id !s IN(SELECT vid FROM wlists WHERE uid = ?)' => [ $o{ul_onwish} ? '' : 'NOT', $uid ] ) : (),
    $uid && defined $o{ul_voted} ? (
      'v.id !s IN(SELECT vid FROM votes WHERE uid = ?)' => [ $o{ul_voted} ? '' : 'NOT', $uid ] ) : (),
    $uid && defined $o{ul_onlist} ? (
      'v.id !s IN(SELECT vid FROM vnlists WHERE uid = ?)' => [ $o{ul_onlist} ? '' : 'NOT', $uid ] ) : (),
    !$o{id} && !$o{inc_hidden} ? (
      'v.hidden = FALSE' => 0 ) : (),
    # optimize fetching random entries (only when there are no other filters present, otherwise this won't work well)
    $o{sort} eq 'rand' && $o{results} <= 10 && !grep(!/^(?:results|page|what|sort|tagspoil)$/, keys %o) ? (
      'v.id IN(SELECT floor(random() * last_value)::integer FROM generate_series(1,20), (SELECT MAX(id) AS last_value FROM vn) s1 LIMIT 20)' ) : (),
  );

  if($o{release}) {
    my($q, @p) = sqlprint
      'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id !W)',
      [ 'NOT r.hidden' => 1, $self->dbReleaseFilters(%{$o{release}}), ];
    push @where, $q, \@p;
  }

  my @join = (
    $o{what} =~ /relgraph/ ?
      'JOIN relgraphs vg ON vg.id = v.rgraph' : (),
    $uid && $o{what} =~ /wishlist/ ?
      'LEFT JOIN wlists wl ON wl.vid = v.id AND wl.uid = ' . $uid : (),
    $uid && $o{what} =~ /vnlist/ ? ("LEFT JOIN (
       SELECT irv.vid, COUNT(*) AS userlist_all,
              SUM(CASE WHEN irl.status = 2 THEN 1 ELSE 0 END) AS userlist_obtained
         FROM rlists irl
         JOIN releases_vn irv ON irv.id = irl.rid
        WHERE irl.uid = $uid
        GROUP BY irv.vid
     ) AS vnlist ON vnlist.vid = v.id") : (),
  );

  my $tag_ids = $o{tag_inc} && join ',', ref $o{tag_inc} ? @{$o{tag_inc}} : $o{tag_inc};
  my @select = ( # see https://rt.cpan.org/Ticket/Display.html?id=54224 for the cast on c_languages and c_platforms
    qw|v.id v.locked v.hidden v.c_released v.c_languages::text[] v.c_platforms::text[] v.title v.original v.rgraph|,
    $o{what} =~ /extended/ ? (
      qw|v.alias v.image v.img_nsfw v.length v.desc v.l_wp v.l_encubed v.l_renai| ) : (),
    $o{what} =~ /relgraph/ ? 'vg.svg' : (),
    $o{what} =~ /rating/ ? (qw|v.c_popularity v.c_rating v.c_votecount|) : (),
    $o{what} =~ /ranking/ ? (
      '(SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_popularity > COALESCE(v.c_popularity, 0.0)) AS p_ranking',
      '(SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_rating > COALESCE(v.c_rating, 0.0)) AS r_ranking',
    ) : (),
    $uid && $o{what} =~ /wishlist/ ? 'wl.wstat' : (),
    $uid && $o{what} =~ /vnlist/ ? (qw|vnlist.userlist_all vnlist.userlist_obtained|) : (),
    # TODO: optimize this, as it will be very slow when the selected tags match a lot of VNs (>1000)
    $tag_ids ?
      qq|(SELECT AVG(tvh.rating) FROM tags_vn_inherit tvh WHERE tvh.tag IN($tag_ids) AND tvh.vid = v.id AND spoiler <= $o{tagspoil} GROUP BY tvh.vid) AS tagscore| : (),
  );

  my $order = sprintf {
    id       => 'v.id %s',
    rel      => 'v.c_released %s, v.title ASC',
    pop      => 'v.c_popularity %s NULLS LAST',
    rating   => 'v.c_rating %s NULLS LAST',
    title    => 'v.title %s',
    tagscore => 'tagscore %s, v.title ASC',
    rand     => 'RANDOM()',
  }->{$o{sort}}, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM vn v
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \@where, $order,
  );

  $_->{svg} && ($_->{svg} = decode_utf8($_->{svg})) for (@$r);
  return _enrich($self, $r, $np, 0, $o{what});
}


sub dbVNGetRev {
  my $self = shift;
  my %o = (what => '', @_);

  $o{rev} ||= $self->dbRow('SELECT MAX(rev) AS rev FROM changes WHERE type = \'v\' AND itemid = ?', $o{id})->{rev};

  # XXX: Too much duplication with code in dbVNGet() here. Can we combine some code here?
  my $uid = $self->authInfo->{id};

  my $select = 'c.itemid AS id, vo.c_released, vo.c_languages::text[], vo.c_platforms::text[], v.title, v.original, vo.rgraph';
  $select .= ', extract(\'epoch\' from c.added) as added, c.requester, c.comments, u.username, c.rev, c.ihid, c.ilock';
  $select .= ', c.id AS cid, NOT EXISTS(SELECT 1 FROM changes c2 WHERE c2.type = c.type AND c2.itemid = c.itemid AND c2.rev = c.rev+1) AS lastrev';
  $select .= ', v.alias, v.image, v.img_nsfw, v.length, v.desc, v.l_wp, v.l_encubed, v.l_renai, vo.hidden, vo.locked' if $o{what} =~ /extended/;
  $select .= ', vo.c_popularity, vo.c_rating, vo.c_votecount' if $o{what} =~ /rating/;
  $select .= ', (SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_popularity > COALESCE(vo.c_popularity, 0.0)) AS p_ranking'
            .', (SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_rating > COALESCE(vo.c_rating, 0.0)) AS r_ranking' if $o{what} =~ /ranking/;

  my $r = $self->dbAll(q|
    SELECT !s
      FROM changes c
      JOIN vn vo ON vo.id = c.itemid
      JOIN vn_hist v ON v.chid = c.id
      JOIN users u ON u.id = c.requester
      WHERE c.type = 'v' AND c.itemid = ? AND c.rev = ?|,
    $select, $o{id}, $o{rev}
  );

  return _enrich($self, $r, 0, 1, $o{what});
}


sub _enrich {
  my($self, $r, $np, $rev, $what) = @_;

  if(@$r && $what =~ /anime|relations|screenshots|staff|seiyuu/) {
    my($col, $hist, $colname) = $rev ? ('cid', '_hist', 'chid') : ('id', '', 'id');
    my %r = map {
      $r->[$_]{anime} = [];
      $r->[$_]{credits} = [];
      $r->[$_]{seiyuu} = [];
      $r->[$_]{relations} = [];
      $r->[$_]{screenshots} = [];
      ($r->[$_]{$col}, $_)
    } 0..$#$r;

    if($what =~ /staff/) {
      push(@{$r->[$r{ delete $_->{xid} }]{credits}}, $_) for (@{$self->dbAll("
        SELECT vs.$colname AS xid, s.id, vs.aid, sa.name, sa.original, s.gender, s.lang, vs.role, vs.note
          FROM vn_staff$hist vs
          JOIN staff_alias sa ON vs.aid = sa.aid
          JOIN staff s ON s.id = sa.id
          WHERE s.hidden = FALSE AND vs.$colname IN(!l)
          ORDER BY vs.role ASC, sa.name ASC",
        [ keys %r ]
      )});
    }

    if($what =~ /seiyuu/) {
      # The seiyuu query needs the VN id to get the VN<->Char spoiler level.
      # Obtaining this ID is different when using the hist table.
      my($vid, $join) = $rev ? ('h.itemid', 'JOIN changes h ON h.id = vs.chid') : ('vs.id', '');
      push(@{$r->[$r{ delete $_->{xid} }]{seiyuu}}, $_) for (@{$self->dbAll("
        SELECT vs.$colname AS xid, s.id, vs.aid, sa.name, sa.original, s.gender, s.lang, c.id AS cid, c.name AS cname, vs.note,
            (SELECT MAX(spoil) FROM chars_vns cv WHERE cv.vid = $vid AND cv.id = c.id) AS spoil
          FROM vn_seiyuu$hist vs
          JOIN staff_alias sa ON vs.aid = sa.aid
          JOIN staff s ON s.id = sa.id
          JOIN chars c ON c.id = vs.cid
          $join
          WHERE s.hidden = FALSE AND vs.$colname IN(!l)
          ORDER BY c.name",
        [ keys %r ]
      )});
    }

    if($what =~ /anime/) {
      push(@{$r->[$r{ delete $_->{xid} }]{anime}}, $_) for (@{$self->dbAll("
        SELECT va.$colname AS xid, a.id, a.year, a.ann_id, a.nfo_id, a.type, a.title_romaji, a.title_kanji, extract('epoch' from a.lastfetch) AS lastfetch
          FROM vn_anime$hist va
          JOIN anime a ON va.aid = a.id
          WHERE va.$colname IN(!l)",
        [ keys %r ]
      )});
    }

    if($what =~ /relations/) {
      push(@{$r->[$r{ delete $_->{xid} }]{relations}}, $_) for(@{$self->dbAll("
        SELECT rel.$colname AS xid, rel.vid AS id, rel.relation, rel.official, v.title, v.original
          FROM vn_relations$hist rel
          JOIN vn v ON rel.vid = v.id
          WHERE rel.$colname IN(!l)",
        [ keys %r ]
      )});
    }

    if($what =~ /screenshots/) {
      push(@{$r->[$r{ delete $_->{xid} }]{screenshots}}, $_) for (@{$self->dbAll("
        SELECT vs.$colname AS xid, s.id, vs.nsfw, vs.rid, s.width, s.height
          FROM vn_screenshots$hist vs
          JOIN screenshots s ON vs.scr = s.id
          WHERE vs.$colname IN(!l)
          ORDER BY vs.scr",
        [ keys %r ]
      )});
    }
  }

  return wantarray ? ($r, $np) : $r;
}


# Updates the edit_* tables, used from dbItemEdit()
# Arguments: { columns in producers_rev + anime + relations + screenshots }
#  screenshots = [ [ scrid, nsfw, rid ], .. ]
#  relations   = [ [ rel, vid ], .. ]
#  anime       = [ aid, .. ]
sub dbVNRevisionInsert {
  my($self, $o) = @_;

  $o->{img_nsfw} = $o->{img_nsfw}?1:0 if exists $o->{img_nsfw};
  my %set = map exists($o->{$_}) ? (qq|"$_" = ?| => $o->{$_}) : (),
    qw|title original desc alias image img_nsfw length l_wp l_encubed l_renai|;
  $self->dbExec('UPDATE edit_vn !H', \%set) if keys %set;

  if($o->{screenshots}) {
    $self->dbExec('DELETE FROM edit_vn_screenshots');
    my $q = join ',', map '(?, ?, ?)', @{$o->{screenshots}};
    my @val = map +($_->{id}, $_->{nsfw}?1:0, $_->{rid}), @{$o->{screenshots}};
    $self->dbExec("INSERT INTO edit_vn_screenshots (scr, nsfw, rid) VALUES $q", @val) if @val;
  }

  if($o->{relations}) {
    $self->dbExec('DELETE FROM edit_vn_relations');
    my $q = join ',', map '(?, ?, ?)', @{$o->{relations}};
    my @val = map +($_->[1], $_->[0], $_->[2]?1:0), @{$o->{relations}};
    $self->dbExec("INSERT INTO edit_vn_relations (vid, relation, official) VALUES $q", @val) if @val;
  }

  if($o->{anime}) {
    $self->dbExec('DELETE FROM edit_vn_anime');
    my $q = join ',', map '(?)', @{$o->{anime}};
    $self->dbExec("INSERT INTO edit_vn_anime (aid) VALUES $q", @{$o->{anime}}) if @{$o->{anime}};
  }

  if($o->{credits}) {
    $self->dbExec('DELETE FROM edit_vn_staff');
    my $q = join ',', ('(?, ?, ?)') x @{$o->{credits}};
    my @val = map +($_->{aid}, $_->{role}, $_->{note}), @{$o->{credits}};
    $self->dbExec("INSERT INTO edit_vn_staff (aid, role, note) VALUES $q", @val) if @val;
  }

  if($o->{seiyuu}) {
    $self->dbExec('DELETE FROM edit_vn_seiyuu');
    my $q = join ',', ('(?, ?, ?)') x @{$o->{seiyuu}};
    my @val = map +($_->{aid}, $_->{cid}, $_->{note}), @{$o->{seiyuu}};
    $self->dbExec("INSERT INTO edit_vn_seiyuu (aid, cid, note) VALUES $q", @val) if @val;
  }
}


# fetches an ID for a new image
sub dbVNImageId {
  return shift->dbRow("SELECT nextval('covers_seq') AS ni")->{ni};
}


# insert a new screenshot and return it's ID
sub dbScreenshotAdd {
  my($s, $width, $height) = @_;
  return $s->dbRow(q|INSERT INTO screenshots (width, height) VALUES (?, ?) RETURNING id|, $width, $height)->{id};
}


# arrayref of screenshot IDs as argument
sub dbScreenshotGet {
  return shift->dbAll(q|SELECT * FROM screenshots WHERE id IN(!l)|, shift);
}


# Fetch random VN + screenshots
# if any arguments are given, it will return one random screenshot for each VN
sub dbScreenshotRandom {
  my($self, @vids) = @_;
  return $self->dbAll(q|
    SELECT s.id AS scr, s.width, s.height, v.id AS vid, v.title
      FROM screenshots s
      JOIN vn_screenshots vs ON vs.scr = s.id
      JOIN vn v ON v.id = vs.id
     WHERE NOT v.hidden AND NOT vs.nsfw
       AND s.id IN(
         SELECT floor(random() * last_value)::integer
           FROM generate_series(1,20), (SELECT MAX(id) AS last_value FROM screenshots) s1
          LIMIT 20
       )
     LIMIT 4|
  ) if !@vids;
  # this query is faster than it looks
  return $self->dbAll(join(' UNION ALL ', map
    q|SELECT s.id AS scr, s.width, s.height, v.id AS vid, v.title, RANDOM() AS position
        FROM (
         SELECT vs2.id, vs2.scr FROM vn_screenshots vs2
          WHERE vs2.id = ? AND NOT vs2.nsfw
          ORDER BY RANDOM() LIMIT 1
        ) vs
        JOIN vn v ON v.id = vs.id
        JOIN screenshots s ON s.id = vs.scr
     |, @vids).' ORDER BY position', @vids);
}


# returns seiyuus that voice characters referenced by $cids in VNs other than $vid
sub dbVNImportSeiyuu {
  my($self, $vid, $cids) = @_;
  return $self->dbAll(q|
    SELECT DISTINCT ON(c.id) c.id AS cid, c.name AS c_name, sa.id AS sid, sa.aid, sa.name
      FROM vn_seiyuu vs
      JOIN chars c ON c.id = vs.cid
      JOIN staff_alias sa ON sa.aid = vs.aid
      WHERE vs.cid IN(!l) AND vs.id <> ?|, $cids, $vid);
}


1;
