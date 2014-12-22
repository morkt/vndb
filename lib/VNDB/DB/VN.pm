
package VNDB::DB::VN;

use strict;
use warnings;
use Exporter 'import';
use VNDB::Func 'gtintype', 'normalize_query';
use Encode 'decode_utf8';

our @EXPORT = qw|dbVNGet dbVNRevisionInsert dbVNImageId dbScreenshotAdd dbScreenshotGet dbScreenshotRandom dbVNHasChar dbVNHasStaff|;


# Options: id, rev, char, search, length, lang, olang, plat, tag_inc, tag_exc, tagspoil,
#   hasani, hasshot, ul_notblack, ul_onwish, results, page, what, sort, reverse, inc_hidden
# What: extended anime relations screenshots relgraph rating ranking changes wishlist vnlist
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
      'v.id = ?' => $o{id} ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(vr.title, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' => 1 ) : (),
    defined $o{length} ? (
      'vr.length IN(!l)' => [ ref $o{length} ? $o{length} : [$o{length}] ]) : (),
    $o{lang} ? (
      'v.c_languages && ARRAY[!l]::language[]' => [ ref $o{lang} ? $o{lang} : [$o{lang}] ]) : (),
    $o{olang} ? (
      'v.c_olang && ARRAY[!l]::language[]' => [ ref $o{olang} ? $o{olang} : [$o{olang}] ]) : (),
    $o{plat} ? (
      'v.c_platforms && ARRAY[!l]::platform[]' => [ ref $o{plat} ? $o{plat} : [$o{plat}] ]) : (),
    defined $o{hasani} ? (
      '!sEXISTS(SELECT 1 FROM vn_anime va WHERE va.vid = vr.id)' => [ $o{hasani} ? '' : 'NOT ' ]) : (),
    defined $o{hasshot} ? (
      '!sEXISTS(SELECT 1 FROM vn_screenshots vs WHERE vs.vid = vr.id)' => [ $o{hasshot} ? '' : 'NOT ' ]) : (),
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
   # don't fetch hidden items unless we ask for an ID
    !$o{id} && !$o{rev} && !$o{inc_hidden} ? (
      'v.hidden = FALSE' => 0 ) : (),
   # optimize fetching random entries (only when there are no other filters present, otherwise this won't work well)
    $o{sort} eq 'rand' && $o{results} <= 10 && !grep(!/^(?:results|page|what|sort|tagspoil)$/, keys %o) ? (
      sprintf 'v.id IN(SELECT floor(random() * last_value)::integer
           FROM generate_series(1,20), (SELECT last_value FROM vn_id_seq) s1
          LIMIT 20)' ) : (),
  );

  my @join = (
    $o{rev} ?
      'JOIN vn v ON v.id = vr.vid' :
      'JOIN vn v ON vr.id = v.latest',
    $o{rev} || $o{what} =~ /changes/ ?
      'JOIN changes c ON c.id = vr.id' : (),
    $o{what} =~ /changes/ ?
      'JOIN users u ON u.id = c.requester' : (),
    $o{what} =~ /relgraph/ ?
      'JOIN relgraphs vg ON vg.id = v.rgraph' : (),
    $uid && $o{what} =~ /wishlist/ ?
      'LEFT JOIN wlists wl ON wl.vid = v.id AND wl.uid = ' . $uid : (),
    $uid && $o{what} =~ /vnlist/ ? ("LEFT JOIN (
       SELECT irv.vid, COUNT(*) AS userlist_all,
              SUM(CASE WHEN irl.status = 2 THEN 1 ELSE 0 END) AS userlist_obtained
         FROM rlists irl
         JOIN releases ir     ON irl.rid = ir.id
         JOIN releases_vn irv ON irv.rid = ir.latest
        WHERE irl.uid = $uid
        GROUP BY irv.vid
     ) AS vnlist ON vnlist.vid = v.id") : (),
  );

  my $tag_ids = $o{tag_inc} && join ',', ref $o{tag_inc} ? @{$o{tag_inc}} : $o{tag_inc};
  my @select = ( # see https://rt.cpan.org/Ticket/Display.html?id=54224 for the cast on c_languages and c_platforms
    qw|v.id v.locked v.hidden v.c_released v.c_languages::text[] v.c_platforms::text[] vr.title vr.original v.rgraph|, 'vr.id AS cid',
    $o{what} =~ /extended/ ? (
      qw|vr.alias vr.image vr.img_nsfw vr.length vr.desc vr.l_wp vr.l_encubed vr.l_renai| ) : (),
    $o{what} =~ /changes/ ? (
      qw|c.requester c.comments v.latest u.username c.rev c.ihid c.ilock|, q|extract('epoch' from c.added) as added|) : (),
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
    id       => 'id %s',
    rel      => 'c_released %s, title ASC',
    pop      => 'c_popularity %s NULLS LAST',
    rating   => 'c_rating %s NULLS LAST',
    title    => 'title %s',
    tagscore => 'tagscore %s',
    rand     => 'RANDOM()',
  }->{$o{sort}}, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM vn_rev vr
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \@where, $order,
  );

  if($o{what} =~ /relgraph/) {
    $_->{svg} = decode_utf8($_->{svg}) for @$r;
  }

  if(@$r && $o{what} =~ /(anime|relations|screenshots)/) {
    my %r = map {
      $r->[$_]{anime} = [];
      $r->[$_]{relations} = [];
      $r->[$_]{screenshots} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;

    if($o{what} =~ /anime/) {
      push(@{$r->[$r{$_->{vid}}]{anime}}, $_) && delete $_->{vid} for (@{$self->dbAll(q|
        SELECT va.vid, a.id, a.year, a.ann_id, a.nfo_id, a.type, a.title_romaji, a.title_kanji, extract('epoch' from a.lastfetch) AS lastfetch
          FROM vn_anime va
          JOIN anime a ON va.aid = a.id
          WHERE va.vid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /relations/) {
      push(@{$r->[$r{$_->{vid1}}]{relations}}, {
        relation => $_->{relation},
        official => $_->{official},
        id => $_->{vid2},
        title => $_->{title},
        original => $_->{original},
      }) for(@{$self->dbAll(q|
        SELECT rel.vid1, rel.vid2, rel.relation, rel.official, vr.title, vr.original
          FROM vn_relations rel
          JOIN vn v ON rel.vid2 = v.id
          JOIN vn_rev vr ON v.latest = vr.id
          WHERE rel.vid1 IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /screenshots/) {
      push(@{$r->[$r{$_->{vid}}]{screenshots}}, $_) && delete $_->{vid} for (@{$self->dbAll(q|
        SELECT vs.vid, s.id, vs.nsfw, vs.rid, s.width, s.height
          FROM vn_screenshots vs
          JOIN screenshots s ON vs.scr = s.id
          WHERE vs.vid IN(!l)
          ORDER BY vs.scr|,
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
    my @val = map +($_->[0], $_->[1]?1:0, $_->[2]), @{$o->{screenshots}};
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
    my @val = map @{$_}[0..2], @{$o->{credits}};
    $self->dbExec("INSERT INTO edit_vn_staff (aid, role, note) VALUES $q", @val) if @val;
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
    SELECT s.id AS scr, s.width, s.height, vr.vid, vr.title
      FROM screenshots s
      JOIN vn_screenshots vs ON vs.scr = s.id
      JOIN vn_rev vr ON vr.id = vs.vid
      JOIN vn v ON v.id = vr.vid AND v.latest = vs.vid
     WHERE NOT v.hidden AND NOT vs.nsfw
       AND s.id IN(
         SELECT floor(random() * last_value)::integer
           FROM generate_series(1,20), (SELECT last_value FROM screenshots_id_seq) s1
          LIMIT 20
       )
     LIMIT 4|
  ) if !@vids;
  # this query is faster than it looks
  return $self->dbAll(join(' UNION ALL ', map
    q|SELECT s.id AS scr, s.width, s.height, vr.vid, vr.title, RANDOM() AS position
        FROM vn v
        JOIN vn_rev vr ON vr.id = v.latest
        JOIN vn_screenshots vs ON vs.vid = v.latest
        JOIN screenshots s ON s.id = vs.scr
       WHERE v.id = ? AND s.id = (
         SELECT vs2.scr
          FROM vn_screenshots vs2
          JOIN vn v2 ON v2.latest = vs2.vid
         WHERE v2.id = v.id AND NOT vs2.nsfw
         ORDER BY RANDOM()
         LIMIT 1
       )|, @vids).' ORDER BY position', @vids);
}


sub dbVNHasChar {
  my($self, $vid) = @_;
  return $self->dbRow(
    'SELECT 1 AS exists FROM chars c JOIN chars_vns cv ON c.latest = cv.cid WHERE cv.vid = ?', $vid
  )->{exists};
}


sub dbVNHasStaff {
  my($self, $vid) = @_;
  return $self->dbRow(
    'SELECT 1 AS exists FROM vn v JOIN vn_staff vs ON v.latest = vs.vid WHERE v.id = ?', $vid
  )->{exists};
}


1;

