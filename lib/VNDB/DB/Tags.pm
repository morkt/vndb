
package VNDB::DB::Tags;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTagGet|;


# %options->{ id page results order what }
# what: parents childs(n)
sub dbTagGet {
  my $self = shift;
  my %o = (
    order => 't.id ASC',
    page => 1,
    results => 10,
    what => '',
    @_
  );

  my %where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT t.id, t.meta, t.name, t.aliases, t.description
      FROM tags t
      !W
      ORDER BY !s|,
    \%where, $o{order}
  );

  if($o{what} =~ /parents/) {
    $_->{parents} = $self->dbAll(q|SELECT lvl, tag, name FROM tag_tree(?, -1, false)|, $_->{id}) for (@$r);
  }

  if($o{what} =~ /childs\((\d+)\)/) {
    $_->{childs} = $self->dbAll(q|SELECT lvl, tag, name FROM tag_tree(?, ?, true)|, $_->{id}, $1) for (@$r);
  }

  #if(@$r && $o{what} =~ /(?:parents)/) {
    #my %r = map {
    #  ($r->[$_]{id}, $_)
    #} 0..$#$r;
  #}

  return wantarray ? ($r, $np) : $r;
}


1;

