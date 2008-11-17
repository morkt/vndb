
package VNDB::DB::VN;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbVNGet|;


# Options: id, rev, results, page, order
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
    qw|v.id v.locked v.hidden v.c_released v.c_languages v.c_platforms vr.title vr.original|
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM vn_rev vr
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \%where, $o{order},
  );

  return wantarray ? ($r, $np) : $r;
}


1;

