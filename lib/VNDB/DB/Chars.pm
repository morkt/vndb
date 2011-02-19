
package VNDB::DB::Chars;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbCharGet dbCharRevisionInsert dbCharImageId|;


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
  push @select, qw|c.hidden c.locked cr.alias cr.desc cr.image cr.b_month cr.b_day cr.s_bust cr.s_waist cr.s_hip cr.height cr.weight cr.bloodt| if $o{what} =~ /extended/;
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


# Updates the edit_* tables, used from dbItemEdit()
# Arguments: { columns in chars_rev },
sub dbCharRevisionInsert {
  my($self, $o) = @_;

  my %set = map exists($o->{$_}) ? (qq|"$_" = ?|, $o->{$_}) : (),
    qw|name original alias desc image b_month b_day s_bust s_waist s_hip height weight bloodt|;
  $self->dbExec('UPDATE edit_char !H', \%set) if keys %set;
}


# fetches an ID for a new image
sub dbCharImageId {
  return shift->dbRow("SELECT nextval('charimg_seq') AS ni")->{ni};
}


1;

