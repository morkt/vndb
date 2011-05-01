
package VNDB::DB::Affiliates;

use strict;
use warnings;
use POSIX 'strftime';
use Exporter 'import';

our @EXPORT = qw|dbAffiliateGet dbAffiliateEdit dbAffiliateDel dbAffiliateAdd|;


# options: id rids affiliate hidden sort reverse
# what: release
sub dbAffiliateGet {
  my($self, %o) = @_;
  $o{sort} ||= 'id';
  $o{reverse} //= 0;

  my %where = (
    $o{id}                 ? ('id = ?' => $o{id}) : (),
    $o{rids}               ? ('rid IN(!l)'    => [$o{rids}]) : (),
    defined($o{affiliate}) ? ('affiliate = ?' => $o{affiliate}) : (),
    defined($o{hidden})    ? ('!s af.hidden'  => $o{hidden} ? '' : 'NOT') : (),
  );

  my $join = $o{what} ? 'JOIN releases r ON r.id = af.rid JOIN releases_rev rr ON rr.id = r.latest' : '';
  my $select = $o{what} ? ', rr.title' : '';

  my $order = sprintf {
    id        => 'af.id %s',
    rel       => 'rr.title %s',
    prio      => 'af.priority %s',
    url       => 'af.url %s',
    lastfetch => 'af.lastfetch %s',
  }->{$o{sort}}, $o{reverse} ? 'DESC' : 'ASC';

  return $self->dbAll(qq|
    SELECT af.id, af.rid, af.hidden, af.priority, af.affiliate, af.url, af.version,
        extract('epoch' from af.lastfetch) as lastfetch, af.price$select
      FROM affiliate_links af
      $join
      !W
     ORDER BY !s|, \%where, $order);
}


sub dbAffiliateDel {
  my($self, $id) = @_;
  $self->dbExec('DELETE FROM affiliate_links WHERE id = ?', $id);
}


sub dbAffiliateEdit {
  my($self, $id, %ops) = @_;
  my %set;
  exists($ops{$_}) && ($set{"$_ = ?"} = $ops{$_}) for(qw|rid priority hidden affiliate url version|);
  return if !keys %set;
  $self->dbExec('UPDATE affiliate_links !H WHERE id = ?', \%set, $id);
}

sub dbAffiliateAdd {
  my($self, %ops) = @_;
  $self->dbExec('INSERT INTO affiliate_links (rid, priority, hidden, affiliate, url, version) VALUES(!l)',
    [@ops{qw| rid priority hidden affiliate url version|}]);
}


1;

