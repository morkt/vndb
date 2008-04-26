#!/usr/bin/perl

use strict;
use warnings;
no warnings 'once';
use File::Path;
use DBI;

# script assumes:
# /static has been created
# /www/files has already been moved
chdir '/www/vndb';


# run the usual SQL update script
system('psql -U vndb < util/updates/update_1.14.sql');

# fix directories
rmtree('data/rg');
rmtree('www/rg');

mkdir 'data/rg';
mkdir 'static/cv';
mkdir 'static/rg';
chmod 0755, qw|data/rg static/cv static/rg|;

for (0..49) {
  $_ = sprintf "%02d",$_;
  mkdir "data/rg/$_";
  mkdir "static/rg/$_";
  mkdir "static/cv/$_";
  chmod 0777, "data/rg/$_", "static/rg/$_", "static/cv/$_";
}


# rename relation graphs
system('util/multi.pl -c "relgraph all"');


# rename cover images
my $sql = DBI->connect(@VNDB::DBLOGIN,
    { RaiseError => 0, PrintError => 1, AutoCommit => 1, pg_enable_utf8 => 1 });
$sql->do('CREATE SEQUENCE covers_seq');
$sql->do('ALTER TABLE vn_rev ADD COLUMN image_id integer NOT NULL DEFAULT 0');
my $q = $sql->prepare('SELECT DISTINCT ENCODE(image,\'hex\') FROM vn_rev WHERE image <> \'\'');
$q->execute();
for (@{$q->fetchall_arrayref([])}) {
  $q = $sql->prepare('SELECT nextval(\'covers_seq\')');
  $q->execute();
  my($id) = $q->fetchrow_array();
  rename 
    sprintf('www/img/%s/%s.jpg', substr($_->[0],0,1), $_->[0]),
    sprintf('static/cv/%02d/%d.jpg', $id%50, $id);
  $sql->do('UPDATE vn_rev SET image_id = ? WHERE image = DECODE(\''.$_->[0].'\', \'hex\')', undef, $id);
}
$sql->do('ALTER TABLE vn_rev DROP COLUMN image');
$sql->do('ALTER TABLE vn_rev RENAME COLUMN image_id TO image');

