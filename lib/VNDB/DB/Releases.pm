
package VNDB::DB::Releases;

use strict;
use warnings;
use POSIX 'strftime';
use Exporter 'import';

our @EXPORT = qw|dbReleaseGet dbReleaseAdd dbReleaseEdit|;


# Options: id vid rev order unreleased page results what
# What: changes vn producers platforms media
sub dbReleaseGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';
  $o{order} ||= 'rr.released ASC';

  my %where = (
    !$o{id} && !$o{rev} ? (
      'r.hidden = FALSE' => 0 ) : (),
    $o{id} ? (
      'r.id = ?' => $o{id} ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
    $o{vid} ? (
      'rv.vid = ?' => $o{vid} ) : (),
    defined $o{unreleased} ? (
      q|rr.released !s ?| => [ $o{unreleased} ? '>' : '<=', strftime('%Y%m%d', gmtime) ] ) : (),
  );

  my @join = (
    $o{rev} ? 'JOIN releases r ON r.id = rr.rid' : 'JOIN releases r ON rr.id = r.latest',
    $o{vid} ? 'JOIN releases_vn rv ON rv.rid = rr.id' : (),
    $o{what} =~ /changes/ || $o{rev} ? (
      'JOIN changes c ON c.id = rr.id',
      'JOIN users u ON u.id = c.requester'
    ) : (),
  );

  my @select = (
    qw|r.id r.locked r.hidden rr.title rr.original rr.gtin rr.catalog rr.language|,
    qw|rr.website rr.released rr.notes rr.minage rr.type rr.patch|, 'rr.id AS cid',
    $o{what} =~ /changes/ ? qw|c.added c.requester c.comments r.latest u.username c.rev| : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM releases_rev rr
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where,  $o{order}
  );

  if(@$r && $o{what} =~ /(vn|producers|platforms|media)/) {
    my %r = map {
      $r->[$_]{producers} = [];
      $r->[$_]{platforms} = [];
      $r->[$_]{media} = [];
      $r->[$_]{vn} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;

    if($o{what} =~ /vn/) {
      push(@{$r->[$r{$_->{rid}}]{vn}}, $_) for (@{$self->dbAll(q|
        SELECT rv.rid, vr.vid, vr.title, vr.original
          FROM releases_vn rv
          JOIN vn v ON v.id = rv.vid
          JOIN vn_rev vr ON vr.id = v.latest
          WHERE rv.rid IN(!l)
          ORDER BY vr.title|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /producers/) {
      push(@{$r->[$r{$_->{rid}}]{producers}}, $_) for (@{$self->dbAll(q|
        SELECT rp.rid, p.id, pr.name, pr.original, pr.type
          FROM releases_producers rp
          JOIN producers p ON rp.pid = p.id
          JOIN producers_rev pr ON pr.id = p.latest
          WHERE rp.rid IN(!l)
          ORDER BY pr.name|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /platforms/) {
      push(@{$r->[$r{$_->{rid}}]{platforms}}, $_->{platform}) for (@{$self->dbAll(q|
        SELECT rid, platform
          FROM releases_platforms
          WHERE rid IN(!l)|,
        [ keys %r ]
      )});
    }

    if($o{what} =~ /media/) {
      ($_->{medium}=~s/\s+//||1)&&push(@{$r->[$r{$_->{rid}}]{media}}, $_) for (@{$self->dbAll(q|
        SELECT rid, medium, qty
          FROM releases_media
          WHERE rid IN(!l)|,
        [ keys %r ]
      )});
    }
  }

  return wantarray ? ($r, $np) : $r;
}


# arguments: id, %options ->( editsum uid + insert_rev )
# returns: ( local revision, global revision )
sub dbReleaseEdit {
  my($self, $rid, %o) = @_;
  my($rev, $cid) = $self->dbRevisionInsert(1, $rid, $o{editsum}, $o{uid});
  insert_rev($self, $cid, $rid, \%o);
  return ($rev, $cid);
}


# arguments: %options ->( editsum uid + insert_rev )
# returns: ( item id, global revision )
sub dbReleaseAdd {
  my($self, %o) = @_;
  my($rid, $cid) = $self->dbItemInsert(1, $o{editsum}, $o{uid});
  insert_rev($self, $cid, $rid, \%o);
  return ($rid, $cid);
}


# helper function, inserts a producer revision
# Arguments: global revision, item id, { columns in releases_rev + vn + producers + media + platforms }
sub insert_rev {
  my($self, $cid, $rid, $o) = @_;

  $self->dbExec(q|
    INSERT INTO releases_rev (id, rid, title, original, gtin, catalog, language, website, released, notes, minage, type, patch)
      VALUES (!l)|,
    [ $cid, $rid, @$o{qw| title original gtin catalog language website released notes minage type patch|} ]);

  $self->dbExec(q|
    INSERT INTO releases_producers (rid, pid)
      VALUES (?, ?)|,
    $cid, $_
  ) for (@{$o->{producers}});

  $self->dbExec(q|
    INSERT INTO releases_platforms (rid, platform)
      VALUES (?, ?)|,
    $cid, $_
  ) for (@{$o->{platforms}});

  $self->dbExec(q|
    INSERT INTO releases_vn (rid, vid)
      VALUES (?, ?)|,
    $cid, $_
  ) for (@{$o->{vn}});

  $self->dbExec(q|
    INSERT INTO releases_media (rid, medium, qty)
      VALUES (?, ?, ?)|,
    $cid, $_->[0], $_->[1]
  ) for (@{$o->{media}});
}


1;

