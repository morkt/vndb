#!/usr/bin/perl

our $S;

open(STDERR, ">&STDOUT"); # warnings and errors can be captured easily this way
$ENV{PATH} = '/usr/bin';  # required for GraphViz

use strict;
use warnings;
use Text::Unidecode;
#use Time::HiRes 'gettimeofday', 'tv_interval';
#BEGIN { $S = [ gettimeofday ]; }
#END   { printf "Done in %.2f s\n", tv_interval($S); }

use Digest::MD5 'md5_hex';
use Time::CTime;
use GraphViz;
use DBI;
use POSIX 'floor';

require '/www/vndb/lib/global.pl';


my $font = 's'; #Comic Sans MSssss';
my @fsize = ( 9, 7, 10 ); # nodes, edges, node_title
my $tmpfile = '/tmp/vndb_graph.gif';
my $destdir = '/www/vndb/static/rg';
my $datdir = '/www/vndb/data/rg';
my $DEBUG = 0;


my %nodes_all = (
  fontname => $font,
  shape => 'plaintext',
  fontsize => $fsize[0],
  style => "setlinewidth(0.5)",
);

my %edge_all = (
  labeldistance => 2.5,
  labelangle => -20,
  labeljust => 'l',
  dir => 'both',
  minlen => 2,
  fontname => $font,
  fontsize => $fsize[1],
  arrowsize => 0.7,
  color => '#69a89a',
#  constraint => 0,
);

my @edge_rel = map {
  {
    %edge_all,
    $VNDB::VRELW->{$_} ? (
      headlabel => $VNDB::VREL->[$_],
      taillabel => $VNDB::VREL->[$_-1],
    ) : $VNDB::VRELW->{$_+1} ? (
      headlabel => $VNDB::VREL->[$_],
      taillabel => $VNDB::VREL->[$_+1],
    ) : (
      label => ' '.$VNDB::VREL->[$_],
    ),
  };
} 0..$#$VNDB::VREL;




my $sql = DBI->connect('dbi:Pg:dbname=vndb', 'vndb', 'passwd',
  { RaiseError => 1, PrintError => 0, AutoCommit => 0, pg_enable_utf8 => 1 });
my %ids; my %nodes;
my %rels; # "v1-v2" => 1
my @done;



sub createGraph { # vid
  my $id = shift;
  %ids = ();
  %nodes = ();
  %rels = ();

  return 0 if grep { $id == $_ } @done;

  my $g = GraphViz->new(
#    width => 700/96,
    height => 2000/96,
    ratio => 'compress',
  );

  getRel($g, $id);
  if(!keys %rels) {
    push @done, $id;
    $sql->do(q|UPDATE vn SET rgraph = 0 WHERE id = ?|, undef, $id);
    return 0;
  }

 # correct order!
  for (sort { $a->[2] cmp $b->[2] } values %nodes) {
    $DEBUG && printf "ADD: %d\n", $_->[0];
    $_->[2] =~ s#^([0-9]{4})([0-9]{2}).+#$1==0?'N/A':$1==9999?'TBA':(($2&&$2>0?($Time::CTime::MoY[$2-1].' '):'').$1)#e;
    $g->add_node($_->[0], %nodes_all, URL => '/v'.$_->[0], tooltip => $_->[1], label => sprintf
      qq|<<TABLE CELLSPACING="0" CELLPADDING="1" BORDER="0" CELLBORDER="1" BGCOLOR="#f0f0f0">
         <TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="3"><FONT POINT-SIZE="$fsize[2]">  %s  </FONT></TD></TR>
         <TR><TD> %s </TD><TD> %s </TD></TR>
      </TABLE>>|,
      $_->[1], $_->[2], $_->[3]);
  }

 # make sure to sort the edges on node release dates
  my @rel = map { [ split(/-/, $_), $rels{$_} ] } keys %rels;
  for (sort { ($ids{$a->[0]}gt$ids{$a->[1]}?$ids{$a->[1]}:$ids{$a->[0]})
          cmp ($ids{$b->[0]}gt$ids{$b->[1]}?$ids{$b->[1]}:$ids{$b->[0]}) } @rel) {

    if($ids{$_->[1]} gt $ids{$_->[0]}) {
      ($_->[0], $_->[1]) = ($_->[1], $_->[0]);
      $_->[2] = reverseRel($_->[2]);
    }
    $g->add_edge($_->[1] => $_->[0], %{$edge_rel[$_->[2]]});
    $DEBUG && printf "ADD %d -> %d\n", $_->[1], $_->[0];
  }


  $DEBUG && print "IMAGE\n";

 # get a new number
  my $gid = $sql->prepare("SELECT nextval('relgraph_seq')");
  $gid->execute;
  $gid = $gid->fetchrow_arrayref->[0];
  my $fn = sprintf '/%02d/%d.', $gid % 50, $gid;

 # save the image & image map
  my $d = $g->as_gif($destdir.$fn.'gif');
  chmod 0666, $destdir.$fn.'gif';

  $DEBUG && print "CMAP\n";
  open my $F, '>', $datdir.$fn.'cmap' or die $!;
  print $F '<!-- V:'.join(',',keys %nodes)." -->\n";
  ($d = $g->as_cmapx) =~ s/(id|name)="[^"]+"/$1="rgraph"/g;
  print $F $d;
  close $F;
  chmod 0666, $datdir.$fn.'cmap';

  $DEBUG && print "UPDATE\n";
 # update the VNs
  $sql->do(sprintf q|
    UPDATE vn
      SET rgraph = %d
      WHERE id IN(%s)|,
    $gid, join(',', keys %ids));
  $DEBUG && print "FIN\n";

  push @done, keys %ids;
  return 1;
}


sub getRel { # gobj, vid
  my($g, $id) = @_;
  $ids{$id} = 0; # false but defined
  $DEBUG && printf "GET: %d\n", $id;
  my $s = $sql->prepare(q|
    SELECT vr1.vid AS vid1, r.vid2, r.relation, vr1.title AS title1, vr2.title AS title2,
      v1.c_released AS date1, v2.c_released AS date2, v1.c_languages AS lang1, v2.c_languages AS lang2
    FROM vn_relations r
    JOIN vn_rev vr1 ON r.vid1 = vr1.id
    JOIN vn v1 ON v1.id = vr1.vid
    JOIN vn v2 ON r.vid2 = v2.id
    JOIN vn_rev vr2 ON v2.id = vr2.vid
    WHERE (r.vid2 = ? OR vr1.vid = ?) AND v1.latest = vr1.id|
  );
  $s->execute($id, $id);
  for my $r (@{$s->fetchall_arrayref({})}) {
    if($r->{vid1} < $r->{vid2}) {
      $rels{$r->{vid1}.'-'.$r->{vid2}} = reverseRel($r->{relation});
    } else {
      $rels{$r->{vid2}.'-'.$r->{vid1}} = $r->{relation};
    }

    for (1,2) {
      my($cid, $title, $date, $lang) = ($r->{'vid'.$_}, $r->{'title'.$_}, $r->{'date'.$_}, $r->{'lang'.$_});
      $title = unidecode($title);
      $title = substr($title, 0, 27).'...' if length($title) > 30;
      $title =~ s/&/&amp;/g;
      $date = sprintf('%08d', $date);
      $nodes{$cid} = [ $cid, $title, $date, $lang ];

      if(!defined $ids{$cid}) {
        $ids{$cid} = $date;
        getRel($g, $cid) if $id != $cid;
      }
    }
  }
}

sub reverseRel { # rel
  return $VNDB::VRELW->{$_[0]} ? $_[0]-1 : $VNDB::VRELW->{$_[0]+1} ? $_[0]+1 : $_[0];
}



if(@ARGV) {
  #print join('-',@ARGV);
  createGraph($_) for (@ARGV);
  $sql->commit;
} else {
  require Time::HiRes;
  my $S = [ Time::HiRes::gettimeofday() ];

 # regenerate all
  my $s = $sql->prepare(q|SELECT id FROM vn|);
  $s->execute();
  my $i = $s->fetchall_arrayref([]);
  for my $id (@$i) {
    print "Processed $id->[0]\n" if createGraph($id->[0]);
  }

 # delete unused
 # opendir(my $D, $destdir) || die $!;
 # for (readdir($D)) {
 #   next if !/^([0-9a-fA-F]{32})\.gif$/;
 #   my $s = $sql->prepare(q|SELECT 1 AS yes FROM vn WHERE rgraph = DECODE(?, 'hex')|);
 #   $s->execute($1);
 #   if(!$s->fetchall_arrayref({})->[0]{yes}) {
 #     printf "Deleting %s\n", $1;
 #     unlink "$datdir/$1.cmap" or die $!;
 #     unlink "$destdir/$1.gif" or die $!;
 #   }
 # }
 # closedir($D);

  $sql->commit;

  printf "Done in %.3f s\n", Time::HiRes::tv_interval($S);
}

