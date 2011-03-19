
package VNDB::DB::Chars;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbCharGet dbCharRevisionInsert dbCharImageId|;


# options: id rev instance traitspoil trait_inc trait_exc what results page
# what: extended traits vns changes
sub dbCharGet {
  my $self = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    traitspoil => 0,
    @_
  );

  my %where = (
    !$o{id} && !$o{rev} ? ( 'c.hidden = FALSE' => 1 ) : (),
    $o{id}  ? ( 'c.id = ?'  => $o{id} ) : (),
    $o{rev} ? ( 'h.rev = ?' => $o{rev} ) : (),
    $o{notid}    ? ( 'c.id <> ?'   => $o{notid} ) : (),
    $o{instance} ? ( 'cr.main = ?' => $o{instance} ) : (),
    $o{vid}      ? ( 'cr.id IN(SELECT cid FROM chars_vns WHERE vid = ?)' => $o{vid} ) : (),
    $o{trait_inc} ? (
      'c.id IN(SELECT cid FROM traits_chars WHERE tid IN(!l) AND spoil <= ? GROUP BY cid HAVING COUNT(tid) = ?)',
      [ ref $o{trait_inc} ? $o{trait_inc} : [$o{trait_inc}], $o{traitspoil}, ref $o{trait_inc} ? $#{$o{trait_inc}}+1 : 1 ]) : (),
    $o{trait_exc} ? (
      'c.id NOT IN(SELECT cid FROM traits_chars WHERE tid IN(!l))' => [ ref $o{trait_exc} ? $o{trait_exc} : [$o{trait_exc}] ] ) : (),
  );

  my @select = (qw|c.id cr.name cr.original|, 'cr.id AS cid');
  push @select, qw|c.hidden c.locked cr.alias cr.desc cr.image cr.b_month cr.b_day cr.s_bust cr.s_waist cr.s_hip cr.height cr.weight cr.bloodt cr.gender cr.main cr.main_spoil| if $o{what} =~ /extended/;
  push @select, qw|h.requester h.comments c.latest u.username h.rev h.ihid h.ilock|, "extract('epoch' from h.added) as added" if $o{what} =~ /changes/;

  my @join;
  push @join, $o{rev} ? 'JOIN chars c ON c.id = cr.cid' : 'JOIN chars c ON cr.id = c.latest';
  push @join, 'JOIN changes h ON h.id = cr.id' if $o{what} =~ /changes/ || $o{rev};
  push @join, 'JOIN users u ON u.id = h.requester' if $o{what} =~ /changes/;

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM chars_rev cr
      !s
      !W|,
    join(', ', @select), join(' ', @join), \%where
  );

  if(@$r && $o{what} =~ /(vns|traits)/) {
    my %r = map {
      $_->{traits} = [];
      $_->{vns} = [];
      ($_->{cid}, $_)
    } @$r;

    if($o{what} =~ /traits/) {
      push @{$r{ delete $_->{cid} }{traits}}, $_ for (@{$self->dbAll(q|
        SELECT ct.cid, ct.tid, ct.spoil, t.name, t."group", tg.name AS groupname
          FROM chars_traits ct
          JOIN traits t ON t.id = ct.tid
          LEFT JOIN traits tg ON tg.id = t."group"
         WHERE cid IN(!l)
         ORDER BY tg."order", t.name|, [ keys %r ]
      )});
    }

    if($o{what} =~ /vns(?:\((\d+)\))?/) {
      push @{$r{ delete $_->{cid} }{vns}}, $_ for (@{$self->dbAll(q|
        SELECT cv.cid, cv.vid, cv.rid, cv.spoil, cv.role, vr.title AS vntitle, rr.title AS rtitle
          FROM chars_vns cv
          JOIN vn v ON cv.vid = v.id
          JOIN vn_rev vr ON vr.id = v.latest
          LEFT JOIN releases r ON cv.rid = r.id
          LEFT JOIN releases_rev rr ON rr.id = r.latest
          !W|, { 'cv.cid IN(!l)' => [[keys %r]], $1 ? ('cv.vid = ?', $1) : () }
      )});
    }
  }
  return wantarray ? ($r, $np) : $r;
}


# Updates the edit_* tables, used from dbItemEdit()
# Arguments: { columns in chars_rev + traits + vns },
sub dbCharRevisionInsert {
  my($self, $o) = @_;

  my %set = map exists($o->{$_}) ? (qq|"$_" = ?|, $o->{$_}) : (),
    qw|name original alias desc image b_month b_day s_bust s_waist s_hip height weight bloodt gender main main_spoil|;
  $self->dbExec('UPDATE edit_char !H', \%set) if keys %set;

  if($o->{traits}) {
    $self->dbExec('DELETE FROM edit_char_traits');
    $self->dbExec('INSERT INTO edit_char_traits (tid, spoil) VALUES (?,?)', $_->[0],$_->[1]) for (@{$o->{traits}});
  }
  if($o->{vns}) {
    $self->dbExec('DELETE FROM edit_char_vns');
    $self->dbExec('INSERT INTO edit_char_vns (vid, rid, spoil, role) VALUES(!l)', $_) for (@{$o->{vns}});
  }
}


# fetches an ID for a new image
sub dbCharImageId {
  return shift->dbRow("SELECT nextval('charimg_seq') AS ni")->{ni};
}



1;

