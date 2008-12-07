
package VNDB::DB::WishList;

use strict;
use warnings;
use Exporter 'import';


our @EXPORT = qw|dbWishListGet dbWishListAdd dbWishListDel|;


# %options->{ uid vid wstat what order page results }
# what: vn
sub dbWishListGet {
  my($self, %o) = @_;

  $o{order} ||= 'wl.wstat ASC';
  $o{page} ||= 1;
  $o{results} ||= 50;
  $o{what} ||= '';

  my %where = (
    'wl.uid = ?' => $o{uid},
    $o{vid} ? ( 'wl.vid = ?' => $o{vid} ) : (),
    defined $o{wstat} ? ( 'wl.wstat = ?' => $o{wstat} ) : (),
  );

  my $select = 'wl.vid, wl.wstat, wl.added';
  my @join;
  if($o{what} =~ /vn/) {
    $select .= ', vr.title, vr.original';
    push @join, 'JOIN vn v ON v.id = wl.vid',
    'JOIN vn_rev vr ON vr.id = v.latest';
  }

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM wlists wl
      !s
      !W
      ORDER BY !s|,
    $select, join(' ', @join), \%where, $o{order},
  );

  return wantarray ? ($r, $np) : $r;
}


# Updates or adds a whishlist item
# Arguments: vid, uid, wstat
sub dbWishListAdd {
  my($self, $vid, $uid, $wstat) = @_;
    $self->dbExec(
      'UPDATE wlists SET wstat = ? WHERE uid = ? AND vid IN(!l)',
      $wstat, $uid, ref($vid) eq 'ARRAY' ? $vid : [ $vid ]
    )
  ||
    $self->dbExec(
      'INSERT INTO wlists (uid, vid, wstat) VALUES(!l)',
      [ $uid, $vid, $wstat ]
    );
}


# Arguments: uid, vids
sub dbWishListDel {
  my($self, $uid, $vid) = @_;
  $self->dbExec(
    'DELETE FROM wlists WHERE uid = ? AND vid IN(!l)',
    $uid, ref($vid) eq 'ARRAY' ? $vid : [ $vid ]
  );
}


1;

