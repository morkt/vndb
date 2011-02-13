
package VNDB::DB::Traits;

# This module is for a large part a copy of VNDB::DB::Tags. I could have chosen
# to modify that module to work for both traits and tags but that would have
# complicated the code, so I chose to maintain two versions with similar
# functionality instead.

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTraitGet dbTraitTree dbTraitEdit dbTraitAdd|;


# Options: id what results page sort reverse
# what: parents childs(n) aliases addedby
# sort: id name added
sub dbTraitGet {
  my $self = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    @_,
  );

  my %where = (
    $o{id} ? ('t.id = ?' => $o{id}) : (),
  );

  my @select = (
    qw|t.id t.meta t.name t.description t.state|,
    q|extract('epoch' from t.added) as added|,
    $o{what} =~ /addedby/ ? ('t.addedby', 'u.username') : (),
  );
  my @join = $o{what} =~ /addedby/ ? 'JOIN users u ON u.id = t.addedby' : ();

  my $order = sprintf {
    id    => 't.id %s',
    name  => 't.name %s',
    added => 't.added %s',
  }->{ $o{sort}||'id' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM traits t
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $order
  );

  if(@$r && $o{what} =~ /aliases/) {
    my %r = map {
      $_->{aliases} = [];
      ($_->{id}, $_->{aliases})
    } @$r;

    push @{$r{$_->{trait}}}, $_->{alias} for (@{$self->dbAll(q|
      SELECT trait, alias FROM traits_aliases WHERE trait IN(!l)|, [ keys %r ]
    )});
  }

  if($o{what} =~ /parents\((\d+)\)/) {
    $_->{parents} = $self->dbTraitTree($_->{id}, $1, 1) for(@$r);
  }

  if($o{what} =~ /childs\((\d+)\)/) {
    $_->{childs} = $self->dbTraitTree($_->{id}, $1) for(@$r);
  }

  return wantarray ? ($r, $np) : $r;
}


# almost much equivalent to dbTagTree
sub dbTraitTree {
  my($self, $id, $lvl, $back) = @_;
  $lvl ||= 15;
  my $r = $self->dbAll(q|
    WITH RECURSIVE traittree(lvl, id, parent, name) AS (
        SELECT ?::integer, id, 0, name
        FROM traits
        !W
      UNION ALL
        SELECT tt.lvl-1, t.id, tt.id, t.name
        FROM traittree tt
        JOIN traits_parents tp ON !s
        JOIN traits t ON !s
        WHERE tt.lvl > 0
          AND t.state = 2
    ) SELECT DISTINCT id, parent, name FROM traittree ORDER BY name|, $lvl,
    $id ? {'id = ?' => $id} : {'NOT EXISTS(SELECT 1 FROM traits_parents WHERE trait = id)' => 1, 'state = 2' => 1},
    !$back ? ('tp.parent = tt.id', 't.id = tp.trait') : ('tp.trait = tt.id', 't.id = tp.parent')
  );
  for my $i (@$r) {
    $i->{'sub'} = [ grep $_->{parent} == $i->{id}, @$r ];
  }
  my @r = grep !delete($_->{parent}), @$r;
  return $id ? $r[0]{'sub'} : \@r;
}


# args: trait id, %options->{ columns in the traits table + parents + aliases }
sub dbTraitEdit {
  my($self, $id, %o) = @_;

  $self->dbExec('UPDATE traits !H WHERE id = ?', {
    $o{upddate} ? ('added = NOW()' => 1) : (),
    map exists($o{$_}) ? ("$_ = ?" => $o{$_}) : (), qw|name meta description state|
  }, $id);
  if($o{aliases}) {
    $self->dbExec('DELETE FROM traits_aliases WHERE trait = ?', $id);
    $self->dbExec('INSERT INTO traits_aliases (trait, alias) VALUES (?, ?)', $id, $_) for (@{$o{aliases}});
  }
  if($o{parents}) {
    $self->dbExec('DELETE FROM traits_parents WHERE trait = ?', $id);
    $self->dbExec('INSERT INTO traits_parents (trait, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  }
}


# same args as dbTraitEdit, without the first trait id
# returns the id of the new trait
sub dbTraitAdd {
  my($self, %o) = @_;
  my $id = $self->dbRow('INSERT INTO traits (name, meta, description, state, addedby) VALUES (!l, ?) RETURNING id',
    [ map $o{$_}, qw|name meta description state| ], $o{addedby}||$self->authInfo->{id}
  )->{id};
  $self->dbExec('INSERT INTO traits_parents (trait, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  $self->dbExec('INSERT INTO traits_aliases (trait, alias) VALUES (?, ?)', $id, $_) for (@{$o{aliases}});
  return $id;
}


1;

