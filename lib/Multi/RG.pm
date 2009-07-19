
#
#  Multi::RG  -  Relation graph generator
#

package Multi::RG;

use strict;
use warnings;
use POE 'Wheel::Run', 'Filter::Stream';
use Encode 'encode_utf8';
use Time::HiRes 'time';


sub spawn {
  my $p = shift;
  POE::Session->create(
    package_states => [
      $p => [qw|
        _start shutdown check_rg creategraph getrel builddot buildgraph savegraph
        proc_stdin proc_stdout proc_stderr proc_closed proc_child
      |],
    ],
    heap => {
      font => 'Arial',
      fsize => [ 9, 7, 10 ], # nodes, edges, node_title
      imgdir => '/www/vndb/static/rg',
      moy => [qw| Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec |],
      dot => '/usr/bin/dot',
      check_delay => 3600,
      @_,
    }
  );
}


sub _start {
  $_[KERNEL]->alias_set('rg');
  $_[KERNEL]->sig(CHLD => 'proc_child');
  $_[KERNEL]->sig(shutdown => 'shutdown');
  $_[KERNEL]->yield('check_rg');
}


sub shutdown {
  $_[KERNEL]->delay('check_rg');
}


sub check_rg {
  return if $_[HEAP]{vid};
  $_[KERNEL]->call(pg => query =>
    'SELECT v.id FROM vn v JOIN vn_relations vr ON vr.vid1 = v.latest WHERE rgraph IS NULL AND hidden = FALSE LIMIT 1',
    undef, 'creategraph');
}


sub creategraph { # num, res
  return $_[KERNEL]->delay('check_rg', $_[HEAP]{check_delay}) if $_[ARG0] == 0;

  $_[HEAP]{start} = time;
  $_[HEAP]{vid} = $_[ARG1][0]{id};
  $_[HEAP]{rels} = {};  # relations (key=vid1-vid2, value=relation)
  $_[HEAP]{nodes} = {}; # nodes (key=vid, value= 0:found, 1:processed)

  $_[KERNEL]->post(pg => query =>
    'SELECT vid2 AS id, relation FROM vn v JOIN vn_relations vr ON vr.vid1 = v.latest WHERE v.id = ?',
    [ $_[HEAP]{vid} ], 'getrel', $_[HEAP]{vid});
}


sub getrel { # num, res, vid
  my $id = $_[ARG2];
  $_[HEAP]{nodes}{$id} = 1;

  for($_[ARG0] > 0 ? @{$_[ARG1]} : ()) {
    $_[HEAP]{rels}{$id.'-'.$_->{id}} = reverserel($_->{relation}) if $id < $_->{id};
    $_[HEAP]{rels}{$_->{id}.'-'.$id} = $_->{relation}             if $id > $_->{id};

    if(!exists $_[HEAP]{nodes}{$_->{id}}) {
      $_[HEAP]{nodes}{$_->{id}} = 0;
      $_[KERNEL]->post(pg => query =>
        'SELECT vid2 AS id, relation FROM vn v JOIN vn_relations vr ON vr.vid1 = v.latest WHERE v.id = ?',
        [ $_->{id} ], 'getrel', $_->{id});
    }
  }

  # do we have all relations now? get VN info
  if(!grep !$_, values %{$_[HEAP]{nodes}}) {
    $_[KERNEL]->post(pg => query =>
      'SELECT v.id, vr.title, v.c_released AS date, v.c_languages AS lang
         FROM vn v JOIN vn_rev vr ON vr.id = v.latest
         WHERE v.id IN('.join(', ', map '?', keys %{$_[HEAP]{nodes}}).')',
      [ keys %{$_[HEAP]{nodes}} ], 'builddot');
  }
}


sub builddot { # num, res
  my $vns = $_[ARG1];

  my $gv =
    qq|graph rgraph {\n|.
    qq|\tratio = "compress"\n|.
    qq|\tgraph [ bgcolor="#ffffff00" ]\n|.
    qq|\tnode [ fontname = "$_[HEAP]{font}", shape = "plaintext",|.
      qq| fontsize = $_[HEAP]{fsize}[0], style = "setlinewidth(0.5)", fontcolor = "#cccccc", color = "#225588" ]\n|.
    qq|\tedge [ labeldistance = 2.5, labelangle = -20, labeljust = 1, minlen = 2, dir = "both",|.
      qq| fontname = $_[HEAP]{font}, fontsize = $_[HEAP]{fsize}[1], arrowsize = 0.7, color = "#225588", fontcolor = "#cccccc" ]\n|;

  # insert all nodes, ordered by release date
  for (sort { $a->{date} <=> $b->{date} } @$vns) {
    my $date = sprintf '%08d', $_->{date};
    $date =~ s#^([0-9]{4})([0-9]{2}).+#$1==0?'N/A':$1==9999?'TBA':(($2&&$2<13?($_[HEAP]{moy}[$2-1].' '):'').$1)#e;

    my $title = $_->{title};
    $title = substr($title, 0, 27).'...' if length($title) > 30;
    $title =~ s/&/&amp;/g;
    $title =~ s/>/&gt;/g;
    $title =~ s/</&lt;/g;

    my $tooltip = $_->{title};
    $tooltip =~ s/\\/\\\\/g;
    $tooltip =~ s/"/\\"/g;

    $gv .= sprintf
      qq|\tv%d [ URL = "/v%d", tooltip = "%s" label=<|.
        q|<TABLE CELLSPACING="0" CELLPADDING="1" BORDER="0" CELLBORDER="1" BGCOLOR="#00000033">|.
          q|<TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="2"><FONT POINT-SIZE="%d">  %s  </FONT></TD></TR>|.
          q|<TR><TD> %s </TD><TD> %s </TD></TR>|.
        qq|</TABLE>> ]\n|,
      $_->{id}, $_->{id}, encode_utf8($tooltip), $_[HEAP]{fsize}[2], encode_utf8($title), $date, $_->{lang}||'N/A';
  }

  # @rels = ([ vid1, vid2, relation, date1, date2 ], ..), for easier processing
  my @rels = map {
    /^([0-9]+)-([0-9]+)$/;
    my $vn1 = (grep $1 == $_->{id}, @$vns)[0];
    my $vn2 = (grep $2 == $_->{id}, @$vns)[0];
    [ $1, $2, $_[HEAP]{rels}{$_}, $vn1->{date}, $vn2->{date} ]
  } keys %{$_[HEAP]{rels}};

  # insert all edges, ordered by release date again
  for (sort { ($a->[3]>$a->[4]?$a->[4]:$a->[3]) <=> ($b->[3]>$b->[4]?$b->[4]:$b->[3]) } @rels) {
    # [older game] -> [newer game]
    if($_->[4] > $_->[3]) {
      ($_->[0], $_->[1]) = ($_->[1], $_->[0]);
      $_->[2] = reverserel($_->[2]);
    }
    my $label = 
      $VNDB::S{vn_relations}[$_->[2]][1]
        ? qq|headlabel = "$VNDB::S{vn_relations}[$_->[2]][0]", taillabel = "$VNDB::S{vn_relations}[$_->[2]-1][0]"| :
      $VNDB::S{vn_relations}[$_->[2]+1][1]
        ? qq|headlabel = "$VNDB::S{vn_relations}[$_->[2]][0]", taillabel = "$VNDB::S{vn_relations}[$_->[2]+1][0]"|
        : qq|label = " $VNDB::S{vn_relations}[$_->[2]][0]"|;
    $gv .= qq|\tv$$_[1] -- v$$_[0] [ $label ]\n|;
  }

  $gv .= "}\n";

  # get ID
  $_[KERNEL]->post(pg => query => 'INSERT INTO relgraph (cmap) VALUES (\'\') RETURNING id', undef, 'buildgraph', \$gv);
}


sub buildgraph { # num, res, \$gv
  $_[HEAP]{gid} = $_[ARG1][0]{id};
  $_[HEAP]{graph} = sprintf('%s/%02d/%d.png', $_[HEAP]{imgdir}, $_[ARG1][0]{id} % 100, $_[ARG1][0]{id});
  $_[HEAP]{cmap} = '';

  # roughly equivalent to:
  #  cat layout.txt | dot -Tpng -o graph.png -Tcmapx
  $_[HEAP]{proc} = POE::Wheel::Run->new(
    Program => $_[HEAP]{dot},
    ProgramArgs => [ '-Tpng', '-o', $_[HEAP]{graph}, '-Tcmapx' ],
    StdioFilter => POE::Filter::Stream->new(),
    StdinEvent => 'proc_stdin',
    StdoutEvent => 'proc_stdout',
    StderrEvent => 'proc_stderr',
    CloseEvent => 'proc_closed',
  );
  $_[HEAP]{proc}->put(${$_[ARG2]});
}


sub savegraph {
  my $vids = join ',', sort map int, keys %{$_[HEAP]{nodes}};

  # chmod graph
  chmod 0666, $_[HEAP]{graph};

  # save the image map in the database
  $_[KERNEL]->post(pg => do => 'UPDATE relgraph SET cmap = ? WHERE id = ?',
    [ "<!-- V:$vids -->\n$_[HEAP]{cmap}", $_[HEAP]{gid} ]);

  # update the VN table
  $_[KERNEL]->post(pg => do => "UPDATE vn SET rgraph = ? WHERE id IN($vids)", [ $_[HEAP]{gid} ]);

  # log
  $_[KERNEL]->call(core => log => 'Generated relation graph in %.2fs, V: %s', time-$_[HEAP]{start}, $vids);

  # clean up
  delete @{$_[HEAP]}{qw| start vid nodes rels gid graph cmap proc |};

  # check for more things to do
  $_[KERNEL]->yield('check_rg');
}



# POE handlers for communication with GraphViz
sub proc_stdin {
  $_[HEAP]{proc}->shutdown_stdin;
}
sub proc_stdout {
  $_[HEAP]{cmap} .= $_[ARG0];
}
sub proc_stderr {
  $_[KERNEL]->call(core => log => 'GraphViz STDERR: %s', $_[ARG0]);
}
sub proc_closed {
  $_[KERNEL]->yield('savegraph');
}
sub proc_child {
  1; # do nothing, just make sure SIGCHLD is handled to reap the process
}



# non-POE helper function
sub reverserel { # relation
  return $VNDB::S{vn_relations}[$_[0]][1] ? $_[0]-1 : $VNDB::S{vn_relations}[$_[0]+1][1] ? $_[0]+1 : $_[0];
}


1;

