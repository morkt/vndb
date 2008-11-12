
package VNDB::DB::Producers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbProducerGet|;


# options: results, page, id, search, char, rev
# what: changes, vn
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
      '(pr.name ILIKE ? OR pr.original ILIKE ?)', [ '%%'.$o{search}.'%%', '%%'.$o{search}.'%%' ] ) : (),
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

  my $select = 'p.id, p.locked, p.hidden, pr.type, pr.name, pr.original, pr.website, pr.lang, pr.desc';
  $select .= ', c.added, c.requester, c.comments, p.latest, pr.id AS cid, u.username, c.rev' if $o{what} =~ /changes/;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM producers_rev pr
      !s
      !W
      ORDER BY pr.name ASC|,
    $select, join(' ', @join), \%where,
  );

  # TODO: get vn
  
  return wantarray ? ($r, $np) : $r;
}


1;
