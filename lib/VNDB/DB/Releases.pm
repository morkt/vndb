
package VNDB::DB::Releases;

use strict;
use warnings;
use POSIX 'strftime';
use Exporter 'import';
use VNDB::Func 'gtintype';

our @EXPORT = qw|dbReleaseGet dbReleaseRevisionInsert|;


# Options: id vid rev unreleased page results what date media sort reverse
#   platforms languages type minage search resolutions freeware doujin
# What: extended changes vn producers platforms media
# Sort: title released minage
sub dbReleaseGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;
  $o{what} ||= '';

  my @where = (
    !$o{id} && !$o{rev} ? ( 'r.hidden = FALSE' => 0       ) : (),
    $o{id}              ? ( 'r.id = ?'         => $o{id}  ) : (),
    $o{rev}             ? ( 'c.rev = ?'        => $o{rev} ) : (),
    $o{vid}             ? ( 'rv.vid = ?'       => $o{vid} ) : (),
    $o{patch}           ? ( 'rr.patch = ?'     => $o{patch}    == 1 ? 1 : 0) : (),
    $o{freeware}        ? ( 'rr.freeware = ?'  => $o{freeware} == 1 ? 1 : 0) : (),
    $o{doujin}          ? ( 'rr.doujin = ?'    => $o{doujin}   == 1 ? 1 : 0) : (),
    defined $o{unreleased} ? (
      q|rr.released !s ?| => [ $o{unreleased} ? '>' : '<=', strftime('%Y%m%d', gmtime) ] ) : (),
    $o{date} ? (
      '(rr.released >= ? AND rr.released <= ?)' => [ $o{date}[0], $o{date}[1] ] ) : (),
    $o{languages} ? (
      'rr.id IN(SELECT irl.rid FROM releases_lang irl JOIN releases ir ON ir.latest = irl.rid WHERE irl.lang IN(!l))', => [ $o{languages} ] ) : (),
    $o{platforms} ? (
      #'EXISTS(SELECT 1 FROM releases_platforms rp WHERE rp.rid = rr.id AND rp.platform IN(!l))' => [ $o{platforms} ] ) : (),
      'rr.id IN(SELECT irp.rid FROM releases_platforms irp JOIN releases ir ON ir.latest = irp.rid WHERE irp.platform IN(!l))' => [ $o{platforms} ] ) : (),
    defined $o{type} ? (
      'rr.type = ?' => $o{type} ) : (),
    $o{minage} ? (
      'rr.minage !s ?' => [ $o{minage}[0] ? '<=' : '>=', $o{minage}[1] ] ) : (),
    $o{media} ? (
      'rr.id IN(SELECT irm.rid FROM releases_media irm JOIN releases ir ON ir.latest = irm.rid WHERE irm.medium IN(!l))' => [ $o{media} ] ) : (),
    $o{resolutions} ? (
      'rr.resolution IN(!l)' => [ $o{resolutions} ] ) : (),
  );

  if($o{search}) {
    for (split /[ -,._]/, $o{search}) {
      s/%//g;
      if(/^\d+$/ && gtintype($_)) {
        push @where, 'rr.gtin = ?', $_;
      } elsif(length($_) > 0) {
        $_ = "%$_%";
        push @where, '(rr.title ILIKE ? OR rr.original ILIKE ? OR rr.catalog = ?)',
          [ $_, $_, $_ ];
      }
    }
  }

  my @join = (
    $o{rev} ? 'JOIN releases r ON r.id = rr.rid' : 'JOIN releases r ON rr.id = r.latest',
    $o{vid} ? 'JOIN releases_vn rv ON rv.rid = rr.id' : (),
    $o{what} =~ /changes/ || $o{rev} ? (
      'JOIN changes c ON c.id = rr.id',
      'JOIN users u ON u.id = c.requester'
    ) : (),
  );

  my @select = (
    qw|r.id rr.title rr.original rr.website rr.released rr.minage rr.type rr.patch|,
    'rr.id AS cid',
    $o{what} =~ /extended/ ? qw|rr.notes rr.catalog rr.gtin rr.resolution rr.voiced rr.freeware rr.doujin rr.ani_story rr.ani_ero r.hidden r.locked| : (),
    $o{what} =~ /changes/ ?
      (qw|c.requester c.comments r.latest u.username c.rev c.ihid c.ilock|, q|extract('epoch' from c.added) as added|) : (),
  );

  my $order = sprintf {
    title    => 'rr.title %s',
    minage   => 'rr.minage %s',
    released => 'rr.released %s',
  }->{ $o{sort}||'released' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM releases_rev rr
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \@where, $order
  );

  if(@$r) {
    my %r = map {
      $r->[$_]{producers} = [];
      $r->[$_]{platforms} = [];
      $r->[$_]{media} = [];
      $r->[$_]{vn} = [];
      $r->[$_]{languages} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;

    push(@{$r->[$r{$_->{rid}}]{languages}}, $_->{lang}) for (@{$self->dbAll(q|
      SELECT rid, lang
        FROM releases_lang
        WHERE rid IN(!l)|,
      [ keys %r ]
    )});

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
        SELECT rp.rid, rp.developer, rp.publisher, p.id, pr.name, pr.original, pr.type
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
      push(@{$r->[$r{$_->{rid}}]{media}}, $_) for (@{$self->dbAll(q|
        SELECT rid, medium, qty
          FROM releases_media
          WHERE rid IN(!l)|,
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
  $self->dbExec('UPDATE edit_release !H', \%set) if keys %set;

  if($o->{languages}) {
    $self->dbExec('DELETE FROM edit_release_lang');
    my $q = join ',', map '(?)', @{$o->{languages}};
    $self->dbExec("INSERT INTO edit_release_lang (lang) VALUES $q", @{$o->{languages}}) if @{$o->{languages}};
  }

  if($o->{producers}) {
    $self->dbExec('DELETE FROM edit_release_producers');
    my $q = join ',', map '(?,?,?)', @{$o->{producers}};
    my @q = map +($_->[0], $_->[1]?1:0, $_->[2]?1:0), @{$o->{producers}};
    $self->dbExec("INSERT INTO edit_release_producers (pid, developer, publisher) VALUES $q", @q) if @q;
  }

  if($o->{platforms}) {
    $self->dbExec('DELETE FROM edit_release_platforms');
    my $q = join ',', map '(?)', @{$o->{platforms}};
    $self->dbExec("INSERT INTO edit_release_platforms (platform) VALUES $q", @{$o->{platforms}}) if @{$o->{platforms}};
  }

  if($o->{vn}) {
    $self->dbExec('DELETE FROM edit_release_vn');
    my $q = join ',', map '(?)', @{$o->{vn}};
    $self->dbExec("INSERT INTO edit_release_vn (vid) VALUES $q", @{$o->{vn}}) if @{$o->{vn}};
  }

  if($o->{media}) {
    $self->dbExec('DELETE FROM edit_release_media');
    my $q = join ',', map '(?,?)', @{$o->{media}};
    my @q = map +($_->[0], $_->[1]), @{$o->{media}};
    $self->dbExec("INSERT INTO edit_release_media (medium, qty) VALUES $q", @q) if @q;
  }
}


1;

