
package VNDB::DB::Discussions;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbThreadGet dbPostGet|;


# Options: id, results, page, what
# what: Nothing, yet
sub dbThreadGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;

  my %where = (
    $o{id} ? (
      't.id = ?' => $o{id} ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT t.id, t.title, t.count, t.locked, t.hidden
      FROM threads t
      !W|,
    \%where
  );

  return wantarray ? ($r, $np) : $r;
}


# Options: tid, num, page, results
sub dbPostGet {
  my($self, %o) = @_;
  $o{results} ||= 50;
  $o{page} ||= 1;

  my %where = (
    'tp.tid = ?' => $o{tid},
    $o{num} ? (
      'tp.num = ?' => $o{num} ) : (),
  );

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT tp.num, tp.date, tp.edited, tp.msg, tp.hidden, tp.uid, u.username
      FROM threads_posts tp
      JOIN users u ON u.id = tp.uid
      !W
      ORDER BY tp.num ASC|,
    \%where,
  );

  return wantarray ? ($r, $np) : $r;
}


1;

