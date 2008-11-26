
package VNDB::DB::VN;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbVNGet dbVNAdd dbVNEdit|;


# Options: id, rev, search, results, page, order, what
# What: extended categories anime relations screenshots relgraph changes
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
   # don't fetch hidden items unless we ask for an ID
    !$o{id} && !$o{rev} ? (
      'v.hidden = FALSE' => 0 ) : (),
  );

  if($o{search}) {
    my @w;
    for (split /[ -,]/, $o{search}) {
      s/%//g;
      next if length($_) < 2;
#      if(VNDB::GTINType($_)) {
#        push @w, 'irr.gtin = ?', $_;
#      } else {
        $_ = "%$_%";
      push @w, '(ivr.title ILIKE ? OR ivr.alias ILIKE ? OR irr.title ILIKE ? OR irr.original ILIKE ?)',
        [ $_, $_, $_, $_ ];
#      }
    }
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
      'JOIN relgraph rg ON rg.id = v.rgraph' : (),
  );

  my @select = (
    qw|v.id v.locked v.hidden v.c_released v.c_languages v.c_platforms vr.title vr.original v.rgraph|, 'vr.id AS cid',
    $o{what} =~ /extended/ ? (
      qw|vr.alias vr.image vr.img_nsfw vr.length vr.desc vr.l_wp vr.l_encubed vr.l_renai vr.l_vnn| ) : (),
    $o{what} =~ /changes/ ? (
      qw|c.added c.requester c.comments v.latest u.username c.rev c.causedby|) : (),
    $o{what} =~ /relgraph/ ? 'rg.cmap' : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM vn_rev vr
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $o{order},
  );

  if(@$r && $o{what} =~ /(categories|anime|relations|screenshots)/) {
    my %r = map {
      $r->[$_]{categories} = [];
      $r->[$_]{anime} = [];
      $r->[$_]{relations} = [];
      $r->[$_]{screenshots} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;

    if($o{what} =~ /categories/) {
      push(@{$r->[$r{$_->{vid}}]{categories}}, [ $_->{cat}, $_->{lvl} ]) for (@{$self->dbAll(q|
        SELECT vid, cat, lvl
          FROM vn_categories
          WHERE vid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /anime/) {
      push(@{$r->[$r{$_->{vid}}]{anime}}, $_) && delete $_->{vid} for (@{$self->dbAll(q|
        SELECT va.vid, a.*
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
  my($rev, $cid) = $self->dbRevisionInsert(0, $id, $o{editsum}, $o{uid});
  insert_rev($self, $cid, $id, \%o);
  return ($rev, $cid);
}


# arguments: %options ->( editsum uid + insert_rev )
# returns: ( item id, global revision )
sub dbVNAdd {
  my($self, %o) = @_;
  my($id, $cid) = $self->dbItemInsert(0, $o{editsum}, $o{uid});
  insert_rev($self, $cid, $id, \%o);
  return ($id, $cid);
}


# helper function, inserts a producer revision
# Arguments: global revision, item id, { columns in producers_rev + categories + anime + relations + screenshots }
#  categories  = [ [ catid, level ], .. ]
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
    INSERT INTO vn_categories (vid, cat, lvl)
      VALUES (?, ?, ?)|,
    $cid, $_->[0], $_->[1]
  ) for (@{$o->{categories}});

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

  if(@{$o->{anime}}) {
    $self->dbExec(q|
      INSERT INTO vn_anime (vid, aid)
        VALUES (?, ?)|,
      $cid, $_
    ) for (@{$o->{anime}});

    # insert unknown anime
    my $a = $self->dbAll(q|
      SELECT id FROM anime WHERE id IN(!l)|,
      $o->{anime});
    $self->dbExec(q|
      INSERT INTO anime (id) VALUES (?)|, $_
    ) for (grep {
      my $ia = $_;
      !(scalar grep $ia == $_->{id}, @$a)
    } @{$o->{anime}});
  }
}


1;

