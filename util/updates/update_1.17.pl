#!/usr/bin/perl

use strict;
use warnings;

# execute update_1.17.sql first
`psql -U vndb < /www/vndb/util/updates/update_1.17.sql`;


use lib '/www/vndb/lib';
BEGIN { require 'global.pl'; }


# modules in the VNDB:: namespace aren't made to be included in
#  frameworks other than VNDB.pm... so we'll just emulate
#  a few functions of the framework to get DB.pm working
package VNDB;

use VNDB::Util::Tools; # for GTINType
use VNDB::Util::DB;

sub AuthInfo { { id => 1 } } # multi
sub ReqIP { '127.0.0.1' }


package main;

my $db = bless {
  _DB => VNDB::Util::DB->new(@VNDB::DBLOGIN),
}, 'VNDB';

my $rids = $db->DBAll(q|
  SELECT r.id, rr.notes
  FROM releases r
  JOIN releases_rev rr ON rr.id = r.latest
  WHERE r.hidden <> 1
    AND r.locked <> 1
    AND rr.notes ILIKE '%JAN%'
    AND rr.gtin = 0
  ORDER BY r.id
|);


my $edits=0;
for my $r (@$rids) {
  my $codes=0;
  $codes++ while($r->{notes} =~ /[0-9]{12,13}/g);
  if($codes > 1) {
    print "$$r{id}: found more than one GTIN-like code...\n";
    next;
  }

  my $jan;
  if($r->{notes} =~ s/[\s\n(]*JAN(?:(?:\s+|-)code)?\s*[:\x{FF1A}]\s*([0-9-]+)[\s\n)]*//i) {
    ($jan = $1) =~ s/-//g;
    if(!VNDB::GTINType($jan)) {
      print "$$r{id}: invalid GTIN code ($jan), ignoring\n";
      next;
    }
  } else {
    print "$$r{id}: matches on 'JAN', but couldn't find the code...\n";
    next;
  }

  my $p = $db->DBGetRelease(id => $r->{id}, what => 'changes vn producers platforms media')->[0];

  $db->DBEditRelease($r->{id},
    (map { $_ => $p->{$_} } qw| title original language website minage type released platforms |),
    producers => [ map { $_->{id} } @{$p->{producers}} ],
    media => [ map { [ $_->{medium}, $_->{qty} ] } @{$p->{media}} ],
    vn => [ map { $_->{vid} } @{$p->{vn}} ],
    gtin => $jan,
    notes => $r->{notes},
    comm => "(automated edit caused by VNDB upgrade to 1.17)\nMoving JAN code from notes to GTIN field."
  );
  $edits++;
}

$db->DBCommit;

print "Modified $edits releases...\n";

