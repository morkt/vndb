
package VNDB::DB::VN;

use strict;
use warnings;
use Exporter 'import';
use VNDB::Func 'gtintype';
use Encode 'decode_utf8';

our @EXPORT = qw|dbVNGet dbVNAdd dbVNEdit dbVNImageId dbVNCache dbScreenshotAdd dbScreenshotGet dbScreenshotRandom|;


# Options: id, rev, char, search, lang, platform, tags_include, tags_exclude, results, page, order, what
# What: extended anime relations screenshots relgraph ranking changes
sub dbVNGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page}    ||= 1;
  $o{order}   ||= 'vr.title ASC';
  $o{what}    ||= '';

  my %where = (
    $o{id} ? (
      'v.id = ?' => $o{id} ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(vr.title, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(vr.title) < 97 OR ASCII(vr.title) > 122) AND (ASCII(vr.title) < 65 OR ASCII(vr.title) > 90)' => 1 ) : (),
    $o{lang} && @{$o{lang}} ? (
      '('.join(' OR ', map "v.c_languages ILIKE '%%$_%%'", @{$o{lang}}).')' => 1 ) : (),
    $o{platform} && @{$o{platform}} ? (
      '('.join(' OR ', map "v.c_platforms ILIKE '%%$_%%'", @{$o{platform}}).')' => 1 ) : (),
    $o{tags_include} && @{$o{tags_include}} ? (
      'v.id IN(SELECT vid FROM tags_vn_bayesian WHERE tag IN(!l) AND spoiler <= ? GROUP BY vid HAVING COUNT(tag) = ?)',
      [ $o{tags_include}[1], $o{tags_include}[0], $#{$o{tags_include}[1]}+1 ]
    ) : (),
    $o{tags_exclude} && @{$o{tags_exclude}} ? (
      'v.id NOT IN(SELECT vid FROM tags_vn_bayesian WHERE tag IN(!l))' => [ $o{tags_exclude} ] ) : (),
   # don't fetch hidden items unless we ask for an ID
    !$o{id} && !$o{rev} ? (
      'v.hidden = FALSE' => 0 ) : (),
  );

  if($o{search}) {
    my @w;
    for (split /[ -,._]/, $o{search}) {
      s/%//g;
      if(/^\d+$/ && gtintype($_)) {
        push @w, 'irr.gtin = ?', $_;
      } elsif(length($_) > 0) {
        $_ = "%$_%";
        push @w, '(ivr.title ILIKE ? OR ivr.original ILIKE ? OR ivr.alias ILIKE ? OR irr.title ILIKE ? OR irr.original ILIKE ?)',
          [ $_, $_, $_, $_, $_ ];
      }
    }
    push @w, '(irr.id IS NULL OR ir.latest = irr.id)' => 1 if @w;
    $where{ q|
      v.id IN(SELECT iv.id
        FROM vn iv
        JOIN vn_rev ivr ON iv.latest = ivr.id
        LEFT JOIN releases_vn irv ON irv.vid = iv.id
        LEFT JOIN releases_rev irr ON irr.id = irv.rid
        LEFT JOIN releases ir ON ir.latest = irr.id
        !W
        GROUP BY iv.id)|
    } = [ \@w ] if @w;
  }

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
    $o{what} =~ /rating/ ?
      'LEFT JOIN vn_ratings r ON r.vid = v.id' : (),
  );

  my $tag_ids = $o{tags_include} && join ',', @{$o{tags_include}[1]};
  my @select = (
    qw|v.id v.locked v.hidden v.c_released v.c_languages v.c_platforms vr.title vr.original v.rgraph v.c_popularity|, 'vr.id AS cid',
    $o{what} =~ /extended/ ? (
      qw|vr.alias vr.image vr.img_nsfw vr.length vr.desc vr.l_wp vr.l_encubed vr.l_renai vr.l_vnn| ) : (),
    $o{what} =~ /changes/ ? (
      qw|c.requester c.comments v.latest u.username c.rev c.causedby|, q|extract('epoch' from c.added) as added|) : (),
    $o{what} =~ /relgraph/ ? 'vg.svg' : (),
    $o{what} =~ /ranking/ ? '(SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_popularity > v.c_popularity) AS ranking' : (),
    $o{what} =~ /rating/ ? 'r.rating, r.votecount' : (),
    $tag_ids ?
      qq|(SELECT AVG(tvb.rating) FROM tags_vn_bayesian tvb WHERE tvb.tag IN($tag_ids) AND tvb.vid = v.id AND spoiler <= $o{tags_include}[0] GROUP BY tvb.vid) AS tagscore| : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM vn_rev vr
      !s
      !W
      ORDER BY !s NULLS LAST|,
    join(', ', @select), join(' ', @join), \%where, $o{order},
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
        id => $_->{vid2},
        title => $_->{title},
        original => $_->{original}
      }) for(@{$self->dbAll(q|
        SELECT rel.vid1, rel.vid2, rel.relation, vr.title, vr.original
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


# arguments: id, %options ->( editsum uid + insert_rev )
# returns: ( local revision, global revision )
sub dbVNEdit {
  my($self, $id, %o) = @_;
  my($rev, $cid) = $self->dbRevisionInsert('v', $id, $o{editsum}, $o{uid});
  insert_rev($self, $cid, $id, \%o);
  return ($rev, $cid);
}


# arguments: %options ->( editsum uid + insert_rev )
# returns: ( item id, global revision )
sub dbVNAdd {
  my($self, %o) = @_;
  my($id, $cid) = $self->dbItemInsert('v', $o{editsum}, $o{uid});
  insert_rev($self, $cid, $id, \%o);
  return ($id, $cid);
}


# helper function, inserts a producer revision
# Arguments: global revision, item id, { columns in producers_rev + anime + relations + screenshots }
#  screenshots = [ [ scrid, nsfw, rid ], .. ]
#  relations   = [ [ rel, vid ], .. ]
#  anime       = [ aid, .. ]
sub insert_rev {
  my($self, $cid, $vid, $o) = @_;

  $o->{img_nsfw} = $o->{img_nsfw}?1:0;
  $self->dbExec(q|
    INSERT INTO vn_rev (id, vid, title, original, "desc", alias, image, img_nsfw, length, l_wp, l_encubed, l_renai, l_vnn)
      VALUES (!l)|,
    [ $cid, $vid, @$o{qw|title original desc alias image img_nsfw length l_wp l_encubed l_renai l_vnn|} ]);

  $self->dbExec(q|
    INSERT INTO vn_screenshots (vid, scr, nsfw, rid)
      VALUES (?, ?, ?, ?)|,
    $cid, $_->[0], $_->[1]?1:0, $_->[2]
  ) for (@{$o->{screenshots}});

  $self->dbExec(q|
    INSERT INTO vn_relations (vid1, vid2, relation)
      VALUES (?, ?, ?)|,
    $cid, $_->[1], $_->[0]
  ) for (@{$o->{relations}});

  $self->dbExec(q|
    INSERT INTO vn_anime (vid, aid)
      VALUES (?, ?)|,
    $cid, $_
  ) for (@{$o->{anime}});
}


# fetches an ID for a new image
sub dbVNImageId {
  return shift->dbRow("SELECT nextval('covers_seq') AS ni")->{ni};
}


# Updates the vn.c_ columns
sub dbVNCache {
  my($self, @vn) = @_;
  $self->dbExec('SELECT update_vncache(?)', $_) for (@vn);
}


# insert a new screenshot and return it's ID
# (no arguments required, as Multi is responsible for filling the entry with information)
sub dbScreenshotAdd {
  return shift->dbRow(q|INSERT INTO screenshots (processed) VALUES(false) RETURNING id|)->{id};
}


# arrayref of screenshot IDs as argument
sub dbScreenshotGet {
  return shift->dbAll(q|SELECT * FROM screenshots WHERE id IN(!l)|, shift);
}


# Fetch random VN + screenshots
sub dbScreenshotRandom {
  return shift->dbAll(q|
    SELECT vs.scr, vr.vid, vr.title
      FROM vn_screenshots vs
      JOIN vn v ON v.latest = vs.vid
      JOIN vn_rev vr ON vr.id = v.latest
      WHERE vs.nsfw = FALSE AND v.hidden = FALSE
      ORDER BY RANDOM()
      LIMIT 4|
  );
}


1;

