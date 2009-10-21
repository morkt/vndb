#!/usr/bin/perl


# Generates a graphviz relation graph of the complete SQL database,
# information is parsed from dump.sql (has to be in the 'current directory').
# outputs the graph in dot format, usable as input to graphviz.
#
# Usage:
#  ./dbgraph.pl | dot -Tpng >dbgraph.png
#
# (this is a rather fast-written Perl hack, don't expect too much)


use strict;
use warnings;


my %subgraphs = (
  'Producers'        => [qw| FFFFCC producers producers_rev producers_relations |],
  'Releases'         => [qw| C8FFC8 releases releases_rev releases_media releases_platforms releases_producers releases_lang releases_vn |],
  'Visual Novels'    => [qw| FFE6BE vn vn_rev vn_relations vn_anime vn_screenshots |],
  'Users'            => [qw| CCFFFF users votes rlists wlists sessions |],
  'Discussion board' => [qw| FFDCDC threads threads_boards threads_posts |],
  'Tags'             => [qw| FFC8C8 tags tags_aliases tags_parents tags_vn |],
  'Misc'             => [qw| F5F5F5 changes anime screenshots stats_cache quotes relgraphs |],
);

my %tables; # table_name => [ [ col1, pri ], ... ]
my @rel; # 'table:col -- table:col', ...

sub parse_dump {
  open my $R, '<', 'dump.sql' or die $!;
  my $in='';
  while (<$R>) {
    chomp;
    if(/^ALTER TABLE ([a-z_]+) +ADD FOREIGN KEY \(([a-z0-9_]+)\) +REFERENCES ([a-z_]+) +\(([a-z0-9_]+)\)/) {
      push @rel, sprintf '%s:%s -- %s:%s', $1, $2, $3, $4;
    }
    if(!$in) {
      next if !/^CREATE TABLE ([a-z_]+) /; 
      $in = $1;
      $tables{$in} = [];
      next;
    }
    if(/^\);/) {
      $in = '';
      next;
    }
    if(/^\s+"?([a-z0-9_]+)"?\s/) {
      push @{$tables{$in}}, [ $1, 0 ];
      $tables{$in}[$#{$tables{$in}}][1] = /PRIMARY KEY/ ? 1 : 0;
      next;
    }
    if(/^\s+PRIMARY KEY\((.+)\)/) {
      for my $c (split /,\s*/, $1) {
        $_->[1]=1 for (grep $_->[0] eq $c, @{$tables{$in}});
      }
    }
  }
  close $R;
}

sub table_node { # table_name
  return $_[0].' [ label=<<TABLE CELLSPACING="0" CELLPADDING="1" BORDER="0">'
    .'<TR><TD BGCOLOR="#99CCFF" BORDER="1">'.$_[0].'</TD></TR>'
    .join('', map {
      '<TR><TD BGCOLOR="#FFFFFF" PORT="'.$_->[0].'" BORDER="1">'.$_->[0].'</TD></TR>'
     } @{$tables{$_[0]}})
    .'</TABLE>> ]';
}


parse_dump;
my $clus=0;
print
  qq|graph G {\n|.
  #qq|  ratio = "compress"\n|.
  #qq|  overlap = "false"\n|.
  #qq|  rankdir = "LR"\n|.
  qq|  node [ shape="plaintext" ]\n|.
  #qq|  edge [ color="#cccccc" ]\n|.
  qq|  labelloc="t"\n|.
  sprintf(qq|  label="VNDB Database Structure (%04d-%02d-%02d)"\n|, (localtime)[5]+1900, (localtime)[4]+1, (localtime)[3]).
  join('', map {
    qq|  subgraph cluster_|.(++$clus).qq| {\n|.
    qq|    label="$_"\n|.
    qq|    bgcolor="#|.shift(@{$subgraphs{$_}}).qq|"\n    |.
    join("\n    ", map table_node($_), @{$subgraphs{$_}}).qq|\n|.
    qq|  }\n|
  }  keys %subgraphs).
  qq|  |.join("\n  ", @rel).qq|\n|.
  qq|}|;

