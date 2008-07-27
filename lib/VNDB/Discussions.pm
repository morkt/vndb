
package VNDB::Discussions;

use strict;
use warnings;
use Exporter 'import';
use POSIX 'ceil';

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;
@EXPORT = qw| TThread TEdit TIndex TTag |;


sub TThread {
  my $self = shift;
  my $id = shift;
  my $page = shift||1;

  my $t = $self->DBGetThreads(id => $id, what => 'tagtitles')->[0];
  return $self->ResNotFound if !$t || $t->{hidden} && !$self->AuthCan('boardmod');

  my $p = $self->DBGetPosts(tid => $id, results => $self->{postsperpage}, page => $page);
  return $self->ResNotFound if !$p->[0];

  $self->ResAddTpl(tthread => {
    t => $t,
    ppp => $self->{postsperpage},
    page => $page,
    p => $p,
  });
}


# tid num action
#  0   0   Start a new thread
#  x   0   Reply to a thread
#  x   1   Edit thread (and first post)
#  x   x   Edit post
sub TEdit {
  my $self = shift;
  my $tid = shift||0;
  my $num = shift||0;
  my $tag = shift||'';

  my $t = $tid && $self->DBGetThreads(id => $tid, what => 'tags')->[0];
  return $self->ResNotFound if $tid && !$t;

  my $p = $num && $self->DBGetPosts(tid => $tid, num => $num)->[0];

  my $frm = {};
  if($self->ReqMethod eq 'POST') {
    $frm = $self->FormCheck(
      { name => 'msg', required => 1, maxlength => 5000 },
      !$tid || $num == 1 ? (
        { name => 'title', required => 1, maxlength => 50 },
        { name => 'tags', required => 1, maxlength => 50 },
      ) : (),
      $self->AuthCan('boardmod') ? (
        { name => 'hide', required => 0 },
        { name => 'lock', required => 0 }
      ) : (),
    );
    $frm->{msg} =~ s/[\r\s\n]$//g;

    my %tags = !$frm->{tags} || $frm->{_err} ? () : map {
      $frm->{_err} = [ 'wrongtag' ] if
        !/^([a-z]{1,2})([0-9]*)$/ || !$VNDB::DTAGS->{$1}
        || $1 eq 'v'  && (!$2 || !$self->DBGetVN(id => $2)->[0])
        #|| $1 eq 'r'  && (!$2 || !$self->DBGetRelease(id => $2)->[0])
        || $1 eq 'p'  && (!$2 || !$self->DBGetProducer(id => $2)->[0])
        || $1 eq 'u'  && (!$2 || !$self->DBGetUser(id => $2)->[0])
        || $1 eq 'an' && !$self->AuthCan('boardmod');
      $1.($2||0) => [ $1, $2||0 ]
    } split / /, $frm->{tags};
    my @tags = values %tags;

    if(!$frm->{_err}) {
      my $otid = $tid;
      if(!$tid || $num == 1) {
        my @tags = 
        my %thread = (
          id => $tid,
          title => $frm->{title},
          tags => \@tags,
          hidden => $frm->{hide},
          locked => $frm->{lock},
        );
        $self->DBEditThread(%thread)       if $tid;   # edit thread
        $tid = $self->DBAddThread(%thread) if !$tid;  # create thread
      }
      
      my %post = (
        tid => $tid,
        num => !$otid ? 1 : $num,
        msg => $frm->{msg},
        hidden => $num != 1 && $frm->{hide},
      );
      $self->DBEditPost(%post)       if $num;   # edit post
      $num = $self->DBAddPost(%post) if !$num;  # add post

      my $pagenum = ceil($num/$self->{postsperpage});
      $pagenum = $pagenum > 1 ? '/'.$pagenum : '';
      $self->ResRedirect('/t'.$tid.$pagenum.'#'.$num, 'POST');
    }
  }

  if($p) {
    $frm->{msg} ||= $p->{msg};
    $frm->{hide} = $p->{hidden};
    if($num == 1) {
      $frm->{tags} ||= join ' ', sort map $_->[1]?$_->[0].$_->[1]:$_->[0], @{$t->{tags}};
      $frm->{title} ||= $t->{title};
      $frm->{lock}  = $t->{locked};
      $frm->{hide}  = $t->{hidden};
    }
  }
  $frm->{tags} ||= $tag;
  
  $self->ResAddTpl(tedit => {
    t => $t,
    p => $p,
    tag => $tag,
    form => $frm,
  });
}


sub TIndex {
  my $self = shift;

  my %opts = (
    results => 6,
    what => 'firstpost lastpost tags',
    order => 'tp2.date DESC',
  );

  $self->ResAddTpl(tindex => {
    ppp => $self->{postsperpage},
    map +($_, scalar $self->DBGetThreads(%opts, type => $_)), qw| an db v p u|
  });
}


sub TTag {
  my $self = shift;
  my $tag = shift;
  my($type, $iid) = ($1, $2||0) if $tag =~ /^([a-z]{1,2})([0-9]*)$/;
  return $self->ResNotFound if !$type;

  my $f = $self->FormCheck(
    { name => 'p', required => 0, default => 1, template => 'int' },
  );
  return $self->ResNotFound if $f->{_err};

  my $o = !$iid ? undef :
    $type eq 'u' ? $self->DBGetUser(uid => $iid)->[0] :
    $type eq 'v' ? $self->DBGetVN(id => $iid)->[0] :
    #$type eq 'r' ? $self->DBGetRelease(id => $iid)->[0] :
                   $self->DBGetProducer(id => $iid)->[0];
  return $self->ResNotFound if $iid && !$o || !$VNDB::DTAGS->{$type};
  my $title = $o ? $o->{username} || $o->{romaji} || $o->{title} || $o->{name} : $VNDB::DTAGS->{$type};

  my($t, $np) = $self->DBGetThreads(
    type => $type,
    iid => $iid,
    results => 50,
    page => $f->{p},
    what => 'firstpost lastpost tagtitles',
    order => $tag eq 'an' ? 't.id DESC' : 'tp2.date DESC',
  );

  $self->ResAddTpl(ttag => {
    page => $f->{p},
    npage => $np,
    obj => $o,
    type => $type,
    iid => $iid,
    title => $title,
    tag => $tag,
    t => $t,
    ppp => $self->{postsperpage},
  });
}



1;

