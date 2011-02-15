
package VNDB::DB::Chars;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbCharGet|;


# options: id rev what results page
# what: extended changes
sub dbCharGet {
  my $self = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    @_
  );

  my %where = (
    !$o{id} && !$o{rev} ? ( 'c.hidden = FALSE' => 1 ) : (),
    $o{id}  ? ( 'c.id = ?'  => $o{id} ) : (),
    $o{rev} ? ( 'h.rev = ?' => $o{rev} ) : (),
  );

  my @select = qw|c.id cr.name cr.original|;
  push @select, qw|c.hidden c.locked cr.alias cr.desc| if $o{what} =~ /extended/;
  push @select, qw|h.requester h.comments c.latest u.username h.rev h.ihid h.ilock|, "extract('epoch' from h.added) as added", 'cr.id AS cid' if $o{what} =~ /changes/;

  my @join;
  push @join, $o{rev} ? 'JOIN chars c ON c.id = cr.cid' : 'JOIN chars c ON cr.id = c.latest';
  push @join, 'JOIN changes h ON h.id = cr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = h.requester' if $o{what} =~ /changes/;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM chars_rev cr
      !s
      !W|,
    join(', ', @select), join(' ', @join), \%where);

  return wantarray ? ($r, $np) : $r;
}


1;

