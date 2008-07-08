
package VNDB::HomePages;

use strict;
use warnings;
use Exporter 'import';

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| HomePage DocPage History HistRevert HistDelete |;


sub HomePage {
  my $self = shift;

  my $an = $self->DBGetThreads(type => 'an', order => 't.id DESC', results => 1)->[0];
  $self->ResAddTpl(home => {
    an          => $an,
    anpost      => $self->DBGetPosts(tid => $an->{id}, num => 1)->[0],
    recentedits => scalar $self->DBGetHist( results => 10, what => 'iid ititle'),
    recentvns   => scalar $self->DBGetHist( results => 10, what => 'iid ititle', edits => 0, type => 'v'),
    recentps    => scalar $self->DBGetHist( results => 10, what => 'iid ititle', edits => 0, type => 'p'),
    recentposts => scalar $self->DBGetThreads(results => 10, what => 'lastpost', order => 'tp2.date DESC'),
   # cache this shit when performance is going to be problematic
    upcomingrel => scalar $self->DBGetRelease(results => 10, unreleased => 1),
    justrel     => scalar $self->DBGetRelease(results => 10, order => 'rr.released DESC', unreleased => 0),
  });
}


sub DocPage {
  my($s,$p) = @_;

  open my $F, '<', sprintf('%s/%d', $s->{docpath}, $p) or return $s->ResNotFound();
  my @c = <$F>;
  close $F;

  (my $title = shift @c) =~ s/^:TITLE://;
  chomp $title;

  my $sec = 0;
  for (@c) {
    s{^:SUB:(.+)\r?\n$}{
      $sec++;
      qq|<h3><a href="#$sec" name="$sec">$sec. $1</a></h3>\n|
    }eg;
    s{^:INC:(.+)\r?\n$}{
      open $F, '<', sprintf('%s/%s', $s->{docpath}, $1) or die $!;
      my $ii = join('', <$F>);
      close $F;
      $ii;
    }eg;
  }

  $s->ResAddTpl(docs => {
    title => $title,
    content => join('', @c),
  });
}


sub History { # type(p,v,r,u), id, [rss.xml|/]
  my($self, $type, $id, $fmt) = @_;
  $type ||= '';
  $id ||= 0;

  $fmt = undef if !$fmt || $fmt eq '/';
  return $self->ResNotFound if $fmt && $fmt ne 'rss.xml';

  my $f = $self->FormCheck(
    { name =>  'p', required => 0, default => 1, template => 'int' },
    { name => 'ip', required => 0, default => 0 },  # hidden option
    { name =>  't', required => 0, default => 'a', enum => [ qw| v r p a | ] },
    { name =>  'e', required => 0, default => 0, enum => [ 0..2 ] },
    { name =>  'r', required => 0, default => $fmt ? 10 : 50, template => 'int' },
    { name =>  'i', required => 0, default => 0, enum => [ 0..1 ] },
    { name =>  'h', required => 0, default => 0, enum => [ 0..2 ] }, # hidden option
  );

  my $o =
    $type eq 'u' ? $self->DBGetUser(uid => $id)->[0] :
    $type eq 'v' ? $self->DBGetVN(id => $id)->[0] :
    $type eq 'r' ? $self->DBGetRelease(id => $id)->[0] :
    $type eq 'p' ? $self->DBGetProducer(id => $id)->[0] :
    undef;
  return $self->ResNotFound if $type && !$o;
  my $t = 
    $type eq 'u' ? $o->{username} :
    $type eq 'v' ? $o->{title} :
    $type eq 'r' ? $o->{romaji} || $o->{title} :
    $type eq 'p' ? $o->{name} :
    undef;

  my($h, $np, $act);

  if($self->ReqMethod ne 'POST' || $fmt) {
    ($h, $np) = $self->DBGetHist(
      what => 'iid ititle user',
      type => $type,
      !$type && $f->{t} ne 'a' ? (
        type => $f->{t} ) : (),
      $f->{e} ? (
        edits => $f->{e} == 1 ? 0 : 1 ) : (),
      id => $id,
      page => $fmt ? 0 : $f->{p},
      results => $f->{r},
      releases => $type eq 'v' ? $f->{i} : 0,
      showhid => $f->{h},
      $f->{ip} ? (
        ip => $f->{ip} ) : (),
    );
  }
  else {
    my $frm = $self->FormCheck(
      { name => 'sel', required => 1, multi => 1 },
      { name => 'post', required => 1, default => 'Mass revert', enum => [ 'Mass revert', 'Mass delete' ] },
    );
    my @s = grep /^[0-9]+$/, @{$frm->{sel}};
    if(!$frm->{_err} && @s) {
      $np = 0;
      $h = $frm->{post} =~ /revert/ ? $self->HistRevert(\@s) : $self->HistDelete(\@s);
      $act = $frm->{post} =~ /revert/ ? 'r' : 'd';
    }
  }

  if(!$fmt) {
    $self->ResAddTpl(hist => {
      title => $t,
      selt => $f->{t},
      sele => $f->{e},
      seli => $f->{i},
      type => $type,
      id => $id,
      hist => $h,
      page => $f->{p},
      npage => $np,
      obj => $o,
      act => $act || '',
    });
  } else {
    my $x = $self->ResStartXML;
    $x->startTag('rss', version => '2.0');
    $x->startTag('channel');
    $x->dataElement('language', 'en');
    $x->dataElement('title', !$type ? 'Recent changes at VNDB.org' : $type eq 'u' ? 'Recent changes by '.$t : 'Edit history of '.$t);
    $x->dataElement('link',  $self->{root_url}.(!$type ? '/hist' : '/'.$type.$id.'/hist'));
  
    for (@$h) {
      my $t = (qw| v r p |)[$_->{type}];
      my $url = $self->{root_url}.'/'.$t.$_->{iid}.'?rev='.$_->{id};
      $_->{comments} = VNDB::Util::Template::tpl::summary($_->{comments})||'[no summary]';
      $x->startTag('item');
      $x->dataElement(title => $_->{ititle});
      $x->dataElement(link => $url);
      $x->dataElement(pubDate => NTL::time2str($_->{requested}));
      $x->dataElement(guid => $url);
      $x->dataElement(description => $_->{comments});
      $x->endTag('item');
    }
  
    $x->endTag('channel');
    $x->endTag('rss');
  }
}




1;

__END__


#############################################################
#           E X P E R I M E N T A L   S T U F F             #
#                                                           #

# !WARNING!: this code has not been updated to reflect the recent database changes!


# !WARNING!: this code uses rather many large SQL queries, use with care...
sub HistRevert { # \@ids
  my($self, $l) = @_;
  my $comm = 'Mass revert to revision %d by %s';

 # first, get objects, remove newly created items and causedby edits and add original edits
  $l = $self->DBGetHist(cid => $l, results => 1000, what => 'iid');
  my @todo;
  for (@$l) {
    next if !$_->{prev}; # remove newly created items
    if($_->{causedby}) { # remove causedby edits
      push @todo, $self->DBGetHist(cid => [ $_->{causedby} ], what => 'iid')->[0]; # add original edit
    } else {
      push @todo, $_;
    }
  }
 
 # second, group all items and remove duplicate edits
  my %todo; # key=type.iid, value = [objects] 
  for my $t (@todo) {
    my $k = $t->{type}.$t->{iid};
    $todo{$k} = [ $t ] and next
      if !$todo{$k};
    push @{$todo{$k}}, $t
      if !grep { $_->{id} == $t->{id} } @{$todo{$k}};
  }

 # third, make sure we don't revert edits we don't want to revert
  #TODO

 # fourth, get the lowest revision of each item to revert to (ignoring intermetiate edits)
  @todo = map { (sort { $a->{id} <=> $b->{id} } @{$todo{$_}})[0] } keys %todo;

 # fifth, actually revert the edits
  my @relupd;
  for (@todo) {

    if($_->{type} == 0) { # visual novel
      my $v = $self->DBGetVN(id => $_->{iid}, rev => $_->{prev}, what => 'extended changes relations')->[0];
      my $old = $self->DBGetVN(id => $_->{iid}, rev => $_->{id}, what => 'relations')->[0];
      my $cid = $self->DBEditVN($_->{iid},
        (map { $_ => $v->{$_} } qw| title desc alias categories comm length l_wp l_cisv l_vnn img_nsfw image|),
        relations => [ map { [ $_->{relation}, $_->{id} ] } @{$v->{relations}} ],
        comm => sprintf($comm, $v->{cid}, $v->{username}),
      );
      my %old = map { $_->{id} => $_->{relation} } @{$old->{relations}};
      my %new = map { $_->{id} => $_->{relation} } @{$v->{relations}};
      push @relupd, $self->VNUpdReverse(\%old, \%new, $_->{iid}, $cid);
    }

    if($_->{type} == 1) { # release
      my $r = $self->DBGetRelease(id => $_->{iid}, rev => $_->{prev}, what => 'producers platforms media vn changes')->[0];
      $self->DBEditRelease($_->{iid},
        (map { $_ => $r->{$_} } qw| title original language website notes minage type released platforms |),
        media => [ map { [ $_->{medium}, $_->{qty} ] } @{$r->{media}} ],
        producers => [ map { $_->{id} } @{$r->{producers}} ],
        comm => sprintf($comm, $r->{cid}, $r->{username}),
        vn => [ map { $_->{vid} } @{$r->{vn}} ],
      );
    }

    if($_->{type} == 2) { # producer
      my $p = $self->DBGetProducer(id => $_->{iid}, rev => $_->{prev}, what => 'changes')->[0];
      $self->DBEditProducer($_->{iid},
        (map { $_ => $p->{$_} } qw| name original website type lang desc |),
        comm => sprintf($comm, $p->{cid}, $p->{username}),
      );
    }
  }
  # update relation graphs
  $self->VNRecreateRel(@relupd) if @relupd;

 # sixth, create report of what happened
  my @done;
  for my $t (@todo, @$l) {
    next if $t->{_status};
    $t->{_status} =
      (scalar grep { $t->{id} == $_->{id} } @todo) ? 'reverted' :
                                    $t->{causedby} ? 'automated' :
                                                     'skipped';
    push @done, $t;
  }
  return \@done;
}


# ONLY DELETES NEWLY CREATED PAGES (for now...)
sub HistDelete { # \@ids
  my ($self, $l) = @_;

 # get objects and add causedby edits
  $l = $self->DBGetHist(cid => $l, results => 1000, what => 'iid');
  my @todo = @$l;
#  for (@$l) {
#    if($_->{causedby}) { # remove causedby edits
#      my $n = $self->DBGetHist(cid => [ $_->{causedby} ])->[0]; # add original edit
#      push @todo, $n, $self->DBGetHist(causedby => $n->{id} ])->[0]; # add causedby edits
#    } else {
#      push @todo, $_;
#    }
#  }

 # remove duplicate edit
  # (not necessary now)
 
 # completely delete newly created items (sort on type to make sure we delete vn's before releases, which is faster)
  my @vns;
  for my $t (sort { $a->{type} <=> $b->{type} } @todo) {
    next if $t->{prev};
    $self->DBDelVN($t->{iid}) if $t->{type} == 0;
    $self->DBDelProducer($t->{iid}) if $t->{type} == 2;
    if($t->{type} == 1) { # we need to know the vn's to remove a release
      my $r = $self->DBGetRelease(id => $t->{iid}, what => 'vn')->[0];
      next if !$r; # we could have deleted this release by deleting the related vn
      $self->DBDelRelease([ map { $_->{vid} } @{$r->{vn}} ], $t->{iid});
    }
  }
 
 # delete individual edits
  #TODO

  return \@todo;
}


