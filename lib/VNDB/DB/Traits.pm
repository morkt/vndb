
package VNDB::DB::Traits;

# This module is for a large part a copy of VNDB::DB::Tags. I could have chosen
# to modify that module to work for both traits and tags but that would have
# complicated the code, so I chose to maintain two versions with similar
# functionality instead.

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTraitGet dbTraitEdit dbTraitAdd|;


# Options: id what results page sort reverse
# what: parents childs(n) addedby
# sort: id name name added items
sub dbTraitGet {
  my $self = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    @_,
  );

  $o{search} =~ s/%//g if $o{search};

  my %where = (
    $o{id} ? ('t.id IN(!l)' => [ ref($o{id}) ? $o{id} : [$o{id}] ]) : (),
    defined $o{state} && $o{state} != -1 ? (
      't.state = ?' => $o{state} ) : (),
    !defined $o{state} && !$o{id} && !$o{name} ? (
      't.state = 2' => 1 ) : (),
    $o{search} ? (
      '(t.name ILIKE ? OR t.alias ILIKE ?)' => [ "%$o{search}%", "%$o{search}%" ] ) : (),
  );

  my @select = (
    qw|t.id t.meta t.name t.description t.state t.alias t."group" t."order" t.sexual t.c_items|,
    'tg.name AS groupname', 'tg."order" AS grouporder', q|extract('epoch' from t.added) as added|,
    $o{what} =~ /addedby/ ? ('t.addedby', 'u.username') : (),
  );
  my @join = $o{what} =~ /addedby/ ? 'JOIN users u ON u.id = t.addedby' : ();
  push @join, 'LEFT JOIN traits tg ON tg.id = t."group"';

  my $order = sprintf {
    id    => 't.id %s',
    name  => 't.name %s',
    group => 'tg."order" %s, t.name %1$s',
    added => 't.added %s',
    items => 't.c_items %s',
  }->{ $o{sort}||'id' }, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM traits t
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $order
  );

  if($o{what} =~ /parents\((\d+)\)/) {
    $_->{parents} = $self->dbTTTree(trait => $_->{id}, $1, 1) for(@$r);
  }

  if($o{what} =~ /childs\((\d+)\)/) {
    $_->{childs} = $self->dbTTTree(trait => $_->{id}, $1) for(@$r);
  }

  return wantarray ? ($r, $np) : $r;
}


# args: trait id, %options->{ columns in the traits table + parents }
sub dbTraitEdit {
  my($self, $id, %o) = @_;

  $self->dbExec('UPDATE traits !H WHERE id = ?', {
    $o{upddate} ? ('added = NOW()' => 1) : (),
    map exists($o{$_}) ? ("\"$_\" = ?" => $o{$_}) : (), qw|name meta description state alias group order sexual|
  }, $id);
  if($o{parents}) {
    $self->dbExec('DELETE FROM traits_parents WHERE trait = ?', $id);
    $self->dbExec('INSERT INTO traits_parents (trait, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  }
}


# same args as dbTraitEdit, without the first trait id
# returns the id of the new trait
sub dbTraitAdd {
  my($self, %o) = @_;
  my $id = $self->dbRow('INSERT INTO traits (name, meta, description, state, alias, "group", "order", sexual, addedby) VALUES (!l, ?) RETURNING id',
    [ map $o{$_}, qw|name meta description state alias group order sexual| ], $o{addedby}||$self->authInfo->{id}
  )->{id};
  $self->dbExec('INSERT INTO traits_parents (trait, parent) VALUES (?, ?)', $id, $_) for(@{$o{parents}});
  return $id;
}


1;

