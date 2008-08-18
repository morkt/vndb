#!/usr/bin/perl


# update_1.22.sql must be executed before this script


use strict;
use warnings;
use DBI;

BEGIN { require '/www/vndb/lib/global.pl' }

my $sql = DBI->connect(@VNDB::DBLOGIN,
  { PrintError => 1, RaiseError => 1, AutoCommit => 0 });

my $q = $sql->prepare('INSERT INTO relgraph (id, cmap) VALUES(?,?)');
for (glob "/www/vndb/data/rg/*/*.cmap") {
  my $id = $1 if /([0-9]+)\.cmap$/;
  open my $F, '<', $_ or die $!;
  $q->execute($id, join "\n", <$F>);
  close $F;
}

$sql->do('ALTER TABLE vn ADD FOREIGN KEY (rgraph) REFERENCES relgraph (id) DEFERRABLE INITIALLY DEFERRED');
$sql->commit;

# it's now safe to delete /data/rg

