#!/usr/bin/perl

use strict;
use warnings;
use DBI;

require '../lib/global.pl';

my $sql = DBI->connect('dbi:Pg:dbname=vndb', 'vndb', 'passwd',
    { RaiseError => 1, PrintError => 0, AutoCommit => 1, pg_enable_utf8 => 1 });

my $q = $sql->prepare('SELECT id, rel_old, language FROM vnr'); $q->execute;
for (@{$q->fetchall_arrayref({})}) { 
  my $rel = sprintf !$_->{rel_old} ? 'Original release' : 
                $_->{rel_old} == 1 ? '%s translation' : '%s rerelease', $VNDB::LANG->{$_->{language}};
  $sql->do('UPDATE vnr SET relation = ? WHERE id = ?', undef, $rel, $_->{id});
}
$sql->do('ALTER TABLE vnr DROP COLUMN rel_old');
