
package VNDB::DB::Releases;

use strict;
use warnings;
use POSIX 'strftime';
use Exporter 'import';
use VNDB::Func 'gtintype';

our @EXPORT = qw|dbReleaseFilters dbReleaseGet dbReleaseGetRev dbReleaseRevisionInsert|;


# Release filters shared by dbReleaseGet and dbVNGet
sub dbReleaseFilters {
  my($self, %o) = @_;
  $o{plat} = [ $o{plat} ] if $o{plat} && !ref $o{plat};
  $o{med}  = [ $o{med}  ] if $o{med}  && !ref $o{med};
  return (
    defined $o{patch}       ? ( 'r.patch = ?'      => $o{patch}    == 1 ? 1 : 0) : (),
    defined $o{freeware}    ? ( 'r.freeware = ?'   => $o{freeware} == 1 ? 1 : 0) : (),
    defined $o{type}        ? ( 'r.type = ?'       => $o{type} ) : (),
    defined $o{date_before} ? ( 'r.released <= ?'  => $o{date_before} ) : (),
    defined $o{date_after}  ? ( 'r.released >= ?'  => $o{date_after} ) : (),
    defined $o{minage}      ? ( 'r.minage IN(!l)'  => [ ref $o{minage}     ? $o{minage}     : [$o{minage}]     ] ) : (),
    defined $o{doujin}      ? ( 'NOT r.patch AND r.doujin = ?'        => $o{doujin} == 1 ? 1 : 0) : (),
    defined $o{resolution}  ? ( 'NOT r.patch AND r.resolution IN(!l)' => [ ref $o{resolution} ? $o{resolution} : [$o{resolution}] ] ) : (),
    defined $o{voiced}      ? ( 'NOT r.patch AND r.voiced IN(!l)'     => [ ref $o{voiced}     ? $o{voiced}     : [$o{voiced}]     ] ) : (),
    defined $o{ani_story}   ? ( 'NOT r.patch AND r.ani_story IN(!l)'  => [ ref $o{ani_story}  ? $o{ani_story}  : [$o{ani_story}]  ] ) : (),
    defined $o{ani_ero}     ? ( 'NOT r.patch AND r.ani_ero IN(!l)'    => [ ref $o{ani_ero}    ? $o{ani_ero}    : [$o{ani_ero}]    ] ) : (),
    defined $o{released}    ? ( 'r.released !s ?'  => [ $o{released} ? '<=' : '>', strftime('%Y%m%d', gmtime) ] ) : (),
    $o{lang} ? (
      'r.id IN(SELECT irl.id FROM releases_lang irl WHERE irl.lang IN(!l))' => [ ref $o{lang} ? $o{lang} : [ $o{lang} ] ] ) : (),
    $o{olang} ? (
      'r.id IN(SELECT irv.id FROM releases_vn irv JOIN vn v ON irv.vid = v.id WHERE v.c_olang && ARRAY[!l]::language[])' => [ ref $o{olang} ? $o{olang} : [ $o{olang} ] ] ) : (),
    $o{plat} ? ('('.join(' OR ',
      grep(/^unk$/, @{$o{plat}}) ? 'NOT EXISTS(SELECT 1 FROM releases_platforms irp WHERE irp.id = r.id)' : (),
      grep(!/^unk$/, @{$o{plat}}) ? 'r.id IN(SELECT irp.id FROM releases_platforms irp WHERE irp.platform IN(!l))' : (),
      ).')', [ [ grep !/^unk$/, @{$o{plat}} ] ]) : (),
    $o{med} ? ('('.join(' OR ',
      grep(/^unk$/, @{$o{med}}) ? 'NOT EXISTS(SELECT 1 FROM releases_media irm WHERE irm.id = r.id)' : (),
      grep(!/^unk$/, @{$o{med}}) ? 'r.id IN(SELECT irm.id FROM releases_media irm WHERE irm.medium IN(!l))' : ()
      ).')', [ [ grep(!/^unk$/, @{$o{med}}) ] ]) : (),
  );
}


# Options: id vid pid released page results what med sort reverse date_before date_after
#   plat lang olang type minage search resolution freeware doujin voiced ani_story ani_ero
# What: extended vn producers platforms media affiliates
# Sort: title released minage
sub dbReleaseGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';

  my @where = (
    !$o{id}                 ? ( 'r.hidden = FALSE' => 0       ) : (),
    $o{id}                  ? ( 'r.id = ?'         => $o{id}  ) : (),
    $o{vid}                 ? ( 'rv.vid IN(!l)'    => [ ref $o{vid} ? $o{vid} : [$o{vid}] ] ) : (),
    $o{pid}                 ? ( 'rp.pid = ?'       => $o{pid} ) : (),
    $self->dbReleaseFilters(%o),
  );

  if($o{search}) {
    for (split /[ -,._]/, $o{search}) {
      s/%//g;
      if(/^\d+$/ && gtintype($_)) {
        push @where, 'r.gtin = ?', $_;
      } elsif(length($_) > 0) {
        $_ = "%$_%";
        push @where, '(r.title ILIKE ? OR r.original ILIKE ? OR r.catalog = ?)',
          [ $_, $_, $_ ];
      }
    }
  }

  my @join = (
    $o{vid} ? 'JOIN releases_vn rv ON rv.id = r.id' : (),
    $o{pid} ? 'JOIN releases_producers rp ON rp.id = r.id' : (),
  );

  my @select = (
    qw|r.id r.title r.original r.website r.released r.minage r.type r.patch|,
    $o{what} =~ /extended/ ? qw|r.notes r.catalog r.gtin r.resolution r.voiced r.freeware r.doujin r.ani_story r.ani_ero r.hidden r.locked| : (),
    $o{pid} ? ('rp.developer', 'rp.publisher') : (),
  );

  my $order = sprintf {
    title       => 'r.title %s,                                   r.released %1$s',
    type        => 'r.patch %s, r.type %1$s,                      r.released %1$s, r.title %1$s',
    publication => 'r.doujin %s, r.freeware %1$s,   r.patch %1$s, r.released %1$s, r.title %1$s',
    resolution  => 'r.resolution %s,                r.patch %2$s, r.released %1$s, r.title %1$s',
    voiced      => 'r.voiced %s,                    r.patch %2$s, r.released %1$s, r.title %1$s',
    ani_ero     => 'r.ani_story %s, r.ani_ero %1$s, r.patch %2$s, r.released %1$s, r.title %1$s',
    released    => 'r.released %s, r.id %1$s',
    minage      => 'r.minage %s,                                  r.released %1$s, r.title %1$s',
    notes       => 'r.notes %s,                                   r.released %1$s, r.title %1$s',
  }->{ $o{sort}||'released' }, $o{reverse} ? 'DESC' : 'ASC', !$o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM releases r
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \@where, $order
  );

  return _enrich($self, $r, $np, 0, $o{what});
}


# options: id, rev, what
# what: extended vn producers platforms media affiliates
sub dbReleaseGetRev {
  my $self = shift;
  my %o = (what => '', @_);

  $o{rev} ||= $self->dbRow('SELECT MAX(rev) AS rev FROM changes WHERE type = \'r\' AND itemid = ?', $o{id})->{rev};

  my $select = 'c.itemid AS id, r.title, r.original, r.website, r.released, r.minage, r.type, r.patch';
  $select .= ', r.notes, r.catalog, r.gtin, r.resolution, r.voiced, r.freeware, r.doujin, r.ani_story, r.ani_ero, ro.hidden, ro.locked' if $o{what} =~ /extended/;
  $select .= ', extract(\'epoch\' from c.added) as added, c.requester, c.comments, u.username, c.rev, c.ihid, c.ilock';
  $select .= ', c.id AS cid, NOT EXISTS(SELECT 1 FROM changes c2 WHERE c2.type = c.type AND c2.itemid = c.itemid AND c2.rev = c.rev+1) AS lastrev';

  my $r = $self->dbAll(q|
    SELECT !s
      FROM changes c
      JOIN releases ro ON ro.id = c.itemid
      JOIN releases_hist r ON r.chid = c.id
      JOIN users u ON u.id = c.requester
      WHERE c.type = 'r' AND c.itemid = ? AND c.rev = ?|,
    $select, $o{id}, $o{rev}
  );

  return _enrich($self, $r, 0, 1, $o{what});
}


sub _enrich {
  my($self, $r, $np, $rev, $what) = @_;

  if(@$r) {
    my($col, $hist, $colname) = $rev ? ('cid', '_hist', 'chid') : ('id', '', 'id');
    my %r = map {
      $r->[$_]{producers} = [];
      $r->[$_]{platforms} = [];
      $r->[$_]{media} = [];
      $r->[$_]{vn} = [];
      $r->[$_]{languages} = [];
      ($r->[$_]{$col}, $_)
    } 0..$#$r;

    push(@{$r->[$r{$_->{xid}}]{languages}}, $_->{lang}) for (@{$self->dbAll("
      SELECT $colname AS xid, lang
        FROM releases_lang$hist
        WHERE $colname IN(!l)",
      [ keys %r ]
    )});

    if($what =~ /vn/) {
      push(@{$r->[$r{$_->{xid}}]{vn}}, $_) for (@{$self->dbAll("
        SELECT rv.$colname AS xid, v.id AS vid, v.title, v.original
          FROM releases_vn$hist rv
          JOIN vn v ON v.id = rv.vid
          WHERE rv.$colname IN(!l)
          ORDER BY v.title",
        [ keys %r ]
      )});
    }

    if($what =~ /producers/) {
      push(@{$r->[$r{$_->{xid}}]{producers}}, $_) for (@{$self->dbAll("
        SELECT rp.$colname AS xid, rp.developer, rp.publisher, p.id, p.name, p.original, p.type
          FROM releases_producers$hist rp
          JOIN producers p ON rp.pid = p.id
          WHERE rp.$colname IN(!l)
          ORDER BY p.name",
        [ keys %r ]
      )});
    }

    if($what =~ /platforms/) {
      push(@{$r->[$r{$_->{xid}}]{platforms}}, $_->{platform}) for (@{$self->dbAll("
        SELECT $colname AS xid, platform
          FROM releases_platforms$hist
          WHERE $colname IN(!l)",
        [ keys %r ]
      )});
    }

    if($what =~ /media/) {
      push(@{$r->[$r{$_->{xid}}]{media}}, $_) for (@{$self->dbAll("
        SELECT $colname AS xid, medium, qty
          FROM releases_media$hist
          WHERE $colname IN(!l)",
        [ keys %r ]
      )});
    }
  }

  return wantarray ? ($r, $np) : $r;
}


# Updates the edit_* tables, used from dbItemEdit()
# Arguments: { columns in releases_rev + languages + vn + producers + media + platforms }
sub dbReleaseRevisionInsert {
  my($self, $o) = @_;

  my %set = map exists($o->{$_}) ? ("$_ = ?", $o->{$_}) : (),
    qw|title original gtin catalog website released notes minage type
       patch resolution voiced freeware doujin ani_story ani_ero|;
  $self->dbExec('UPDATE edit_releases !H', \%set) if keys %set;

  if($o->{languages}) {
    $self->dbExec('DELETE FROM edit_releases_lang');
    my $q = join ',', map '(?)', @{$o->{languages}};
    $self->dbExec("INSERT INTO edit_releases_lang (lang) VALUES $q", @{$o->{languages}}) if @{$o->{languages}};
  }

  if($o->{producers}) {
    $self->dbExec('DELETE FROM edit_releases_producers');
    my $q = join ',', map '(?,?,?)', @{$o->{producers}};
    my @q = map +($_->[0], $_->[1]?1:0, $_->[2]?1:0), @{$o->{producers}};
    $self->dbExec("INSERT INTO edit_releases_producers (pid, developer, publisher) VALUES $q", @q) if @q;
  }

  if($o->{platforms}) {
    $self->dbExec('DELETE FROM edit_releases_platforms');
    my $q = join ',', map '(?)', @{$o->{platforms}};
    $self->dbExec("INSERT INTO edit_releases_platforms (platform) VALUES $q", @{$o->{platforms}}) if @{$o->{platforms}};
  }

  if($o->{vn}) {
    $self->dbExec('DELETE FROM edit_releases_vn');
    my $q = join ',', map '(?)', @{$o->{vn}};
    $self->dbExec("INSERT INTO edit_releases_vn (vid) VALUES $q", @{$o->{vn}}) if @{$o->{vn}};
  }

  if($o->{media}) {
    $self->dbExec('DELETE FROM edit_releases_media');
    my $q = join ',', map '(?,?)', @{$o->{media}};
    my @q = map +($_->[0], $_->[1]), @{$o->{media}};
    $self->dbExec("INSERT INTO edit_releases_media (medium, qty) VALUES $q", @q) if @q;
  }
}


1;

