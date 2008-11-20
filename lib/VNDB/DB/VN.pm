
package VNDB::DB::VN;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbVNGet|;


# Options: id, rev, results, page, order, what
# What: extended categories anime relations
sub dbVNGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page}    ||= 1;
  $o{order}   ||= 'vr.title ASC';

  my %where = (
    $o{id} ? (
      'v.id = ?' => $o{id} ) : (),
    $o{rev} ? (
      'vr.id = ?' => $o{rev} ) : (),
   # don't fetch hidden items unless we ask for an ID
    !$o{id} && !$o{rev} ? (
      'v.hidden = FALSE' => 0 ) : (),
  );

  my @join = (
    $o{rev} ?
      'JOIN vn v ON v.id = vr.vid' :
      'JOIN vn v ON vr.id = v.latest',
  );

  my @select = (
    qw|v.id v.locked v.hidden v.c_released v.c_languages v.c_platforms vr.title vr.original|, 'vr.id AS cid',
    $o{what} =~ /extended/ ? (
      qw|vr.alias vr.image vr.img_nsfw vr.length vr.desc vr.l_wp vr.l_encubed vr.l_renai vr.l_vnn| ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM vn_rev vr
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $o{order},
  );

  if(@$r && $o{what} =~ /(categories|anime|relations)/) {
    my %r = map {
      $r->[$_]{categories} = [];
      $r->[$_]{anime} = [];
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
  }

  return wantarray ? ($r, $np) : $r;
}


1;

