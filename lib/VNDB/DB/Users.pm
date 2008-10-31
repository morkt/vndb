
package VNDB::DB::Users;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = 'dbUserGet';


# %options->{ username passwd order uid results page }
sub dbUserGet { 
  my $s = shift;
  my %o = (
    order => 'username ASC',
    page => 1,
    results => 10,
    what => '',
    @_
  );

  my %where = (
    $o{username} ? (
      'username = ?' => $o{username} ) : (),
    $o{passwd} ? (
      'passwd = decode(?, \'hex\')' => $o{passwd} ) : (),
    $o{uid} ? (
      'id = ?' => $o{uid} ) : (),
    !$o{uid} && !$o{username} ? (
      'id > 0' => 1 ) : (),
  );

  my($r, $np) = $s->dbPage(\%o, q|
    SELECT *
      FROM users u
      !W
      ORDER BY !s|,
    \%where,
    $o{order}
  );

  return wantarray ? ($r, $np) : $r;
}


1;
