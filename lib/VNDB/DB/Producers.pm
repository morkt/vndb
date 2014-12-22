
package VNDB::DB::Producers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbProducerGet dbProducerRevisionInsert dbProducerNames|;


# options: results, page, id, search, char, rev
# what: extended changes relations relgraph
sub dbProducerGet {
  my $self = shift;
  my %o = (
    results => 10,
    page => 1,
    what => '',
    @_
  );

  $o{search} =~ s/%//g if $o{search};

  my %where = (
    !$o{id} && !$o{rev} ? (
      'p.hidden = FALSE' => 1 ) : (),
    $o{id} ? (
      'p.id = ?' => $o{id} ) : (),
    $o{search} ? (
      '(pr.name ILIKE ? OR pr.original ILIKE ? OR pr.alias ILIKE ?)', [ map '%%'.$o{search}.'%%', 1..3 ] ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(pr.name, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(pr.name) < 97 OR ASCII(pr.name) > 122) AND (ASCII(pr.name) < 65 OR ASCII(pr.name) > 90)' => 1 ) : (),
    $o{rev} ? (
      'c.rev = ?' => $o{rev} ) : (),
  );

  my @join;
  push @join, $o{rev} ? 'JOIN producers p ON p.id = pr.pid' : 'JOIN producers p ON pr.id = p.latest';
  push @join, 'JOIN changes c ON c.id = pr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = c.requester' if $o{what} =~ /changes/;
  push @join, 'JOIN relgraphs pg ON pg.id = p.rgraph' if $o{what} =~ /relgraph/;

  my $select = 'p.id, pr.type, pr.name, pr.original, pr.lang, pr.id AS cid, p.rgraph';
  $select .= ', pr.desc, pr.alias, pr.website, pr.l_wp, p.hidden, p.locked' if $o{what} =~ /extended/;
  $select .= q|, extract('epoch' from c.added) as added, c.requester, c.comments, p.latest, pr.id AS cid, u.username, c.rev, c.ihid, c.ilock| if $o{what} =~ /changes/;
  $select .= ', pg.svg' if $o{what} =~ /relgraph/;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM producers_rev pr
      !s
      !W
      ORDER BY pr.name ASC|,
    $select, join(' ', @join), \%where,
  );

  if(@$r && $o{what} =~ /relations/) {
    my %r = map {
      $r->[$_]{relations} = [];
      ($r->[$_]{cid}, $_)
    } 0..$#$r;

    push @{$r->[$r{$_->{pid1}}]{relations}}, $_ for(@{$self->dbAll(q|
      SELECT rel.pid1, rel.pid2 AS id, rel.relation, pr.name, pr.original
        FROM producers_relations rel
        JOIN producers p ON rel.pid2 = p.id
        JOIN producers_rev pr ON p.latest = pr.id
        WHERE rel.pid1 IN(!l)|,
      [ keys %r ]
    )});
  }

  return wantarray ? ($r, $np) : $r;
}


# Updates the edit_* tables, used from dbItemEdit()
# Arguments: { columns in producers_rev + relations },
sub dbProducerRevisionInsert {
  my($self, $o) = @_;

  my %set = map exists($o->{$_}) ? (qq|"$_" = ?|, $o->{$_}) : (),
    qw|name original website l_wp type lang desc alias|;
  $self->dbExec('UPDATE edit_producer !H', \%set) if keys %set;

  if($o->{relations}) {
    $self->dbExec('DELETE FROM edit_producer_relations');
    my $q = join ',', map '(?,?)', @{$o->{relations}};
    my @q = map +($_->[1], $_->[0]), @{$o->{relations}};
    $self->dbExec("INSERT INTO edit_producer_relations (pid, relation) VALUES $q", @q) if @q;
  }
}


sub dbProducerNames {
  my($self, @ids) = @_;
  return $self->dbAll(q|
    SELECT p.id, pr.name
      FROM producers p
      JOIN producers_rev pr ON pr.id = p.latest
      WHERE p.id IN (!l)|, \@ids
  );
}


1;

