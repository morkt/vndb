
package VNDB::Handler::VNEdit;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{v(?:([1-9]\d*)(?:\.([1-9]\d*))?/edit|/new)}
    => \&edit,
);


sub edit {
  my($self, $vid, $rev) = @_;

  my $v = $vid && $self->dbVNGet(id => $vid, what => 'extended screenshots relations anime categories changes', $rev ? (rev => $rev) : ())->[0];
  return 404 if $vid && !$v->{id};
  $rev = undef if $v->{cid} == $v->{latest};

  return $self->htmlDenied if !$self->authCan('edit')
    || $vid && ($v->{locked} && !$self->authCan('lock') || $v->{hidden} && !$self->authCan('del'));

  my %b4 = !$vid ? () : (
    (map { $_ => $v->{$_} } qw|title original desc alias length l_wp l_encubed l_renai l_vnn |),
    anime => join(' ', sort { $a <=> $b } map $_->{id}, @{$v->{anime}}),
    categories => join(',', map $_->[0].$_->[1], sort { $a->[0] cmp $b->[0] } @{$v->{categories}}),
  );

  my $frm;
  if($self->reqMethod eq 'POST') {
    $frm = $self->formValidate(
      { name => 'title',     maxlength => 250 },
      { name => 'original',  required => 0, maxlength => 250, default => '' },
      { name => 'alias',     required => 0, maxlength => 500, default => '' },
      { name => 'desc',      maxlength => 10240 },
      { name => 'length',    required => 0, default => 0,  enum => [ 0..$#{$self->{vn_lengths}} ] },
      { name => 'l_wp',      required => 0, default => '', maxlength => 150 },
      { name => 'l_encubed', required => 0, default => '', maxlength => 100 },
      { name => 'l_renai',   required => 0, default => '', maxlength => 100 },
      { name => 'l_vnn',     required => 0, default => 0,  template => 'int' },
      { name => 'anime',     required => 0, default => '' },
      { name => 'categories',required => 0, default => '', maxlength => 1000 },
      { name => 'editsum',   maxlength => 5000 },
    );

    if(!$frm->{_err}) {
      # parse and re-sort fields that have multiple representations of the same information
      my $anime = [ grep /^[0-9]+$/, split /[ ,]+/, $frm->{anime} ];
      my $categories = [ map { [ substr($_,0,3), substr($_,3,1) ] } split /,/, $frm->{categories} ];

      $frm->{anime} = join ' ', sort { $a <=> $b } @$anime;

      # nothing changed? just redirect
      return $self->resRedirect("/v$vid", 'post')
        if $vid && !grep $frm->{$_} ne $b4{$_}, keys %b4;

      my %args = (
        (map { $_ => $frm->{$_} } qw|title original alias desc length l_wp l_encubed l_renai l_vnn editsum|),
        anime => $anime,
        categories => $categories,

        # copy these from $v, as we don't have a form interface for them yet
        image => $v->{image}||0,
        img_nsfw => $v->{img_nsfw},
        screenshots => [ map [ $_->{id}, $_->{nsfw}, $_->{rid} ], @{$v->{screenshots}} ],
        relations => [ map [ $_->{relation}, $_->{id} ], @{$v->{relations}} ],
      );

      $rev = 1;
      ($rev) = $self->dbVNEdit($vid, %args) if $vid;
      ($vid) = $self->dbVNAdd(%args) if !$vid;

      $self->multiCmd("ircnotify v$vid.$rev");
      $self->multiCmd('anime') if $vid && $frm->{anime} ne $b4{anime} || !$vid && $frm->{anime};

      return $self->resRedirect("/v$vid.$rev", 'post');
    }
  }

  !exists $frm->{$_} && ($frm->{$_} = $b4{$_}) for (keys %b4);
  $frm->{editsum} = sprintf 'Reverted to revision v%d.%d', $vid, $rev if $rev && !defined $frm->{editsum};

  $self->htmlHeader(js => 'forms', title => $vid ? "Edit $v->{title}" : 'Add a new visual novel');
  $self->htmlMainTabs('v', $v, 'edit') if $vid;
  $self->htmlEditMessage('v', $v);
  _form($self, $v, $frm);
  $self->htmlFooter;
}


sub _form {
  my($self, $v, $frm) = @_;
  $self->htmlForm({ frm => $frm, action => $v ? "/v$v->{id}/edit" : '/v/new', editsum => 1 },
  'General info' => [
    [ input    => short => 'title',     name => 'Title (romaji)' ],
    [ input    => short => 'original',  name => 'Original title' ],
    [ static   => content => 'The original title of this visual novel, leave blank if it already is in the Latin alphabet.' ],
    [ textarea => short => 'alias',     name => 'Aliases', rows => 4 ],
    [ static   => content => q|
        Comma seperated list of alternative titles or abbreviations. Can include both official
        (japanese/english) titles and unofficial titles used around net.<br />
        <b>Titles that are listed in the releases do not have to be added here.</b>
      |],
    [ textarea => short => 'desc',      name => 'Description', rows => 10 ],
    [ static   => content => q|
        Short description of the main story. Please do not include spoilers, and don't forget to list
        the source in case you didn't write the description yourself. (formatting codes are allowed)
      |],
    [ select   => short => 'length',    name => 'Length', width => 300, options =>
      [ map [ $_ => $self->{vn_lengths}[$_][0].($_ ? " ($self->{vn_lengths}[$_][2])" : '') ], 0..$#{$self->{vn_lengths}} ] ],

    [ input    => short => 'l_wp',      name => 'External links', pre => 'http://en.wikipedia.org/wiki/' ],
    [ input    => short => 'l_encubed', pre => 'http://novelnews.net/tag/', post => '/' ],
    [ input    => short => 'l_renai',   pre => 'http://renai.us/game/', post => '.shtml' ],
    [ input    => short => 'l_vnn',     pre => 'http://visual-novels.net/vn/index.php?option=com_content&amp;task=view&amp;id=', width => 40 ],
    
    [ input    => short => 'anime',     name => 'Anime' ],
    [ static   => content => q|
        Whitespace seperated list of <a href="http://anidb.net/">AniDB</a> anime IDs.
        E.g. "1015 3348" will add <a href="http://anidb.net/a1015">Shingetsutan Tsukihime</a>
        and <a href="http://anidb.net/a3348">Fate/stay night</a> as related anime.<br />
        <b>Note:</b> It can take a few minutes for the anime titles to appear on the VN page.
      |],
  ],

  'Categories' => [
    [ hidden   => short => 'categories' ],
    [ static   => nolabel => 1, content => eval {
       my $r = 'Please read the <a href="/d1">category descriptions</a> before modifying categories!<br /><br />'
       .'<ul>';
       for my $c (qw| e g t p h l s |) {
         $r .= ($c !~ /[thl]/ ? '<li>' : '<br />').$self->{categories}{$c}[0].'<a href="/d1#'.$self->{categories}{$c}[2].'" class="help">?</a><ul>';
         for (sort keys %{$self->{categories}{$c}[1]}) {
           $r .= sprintf '<li><a href="#" id="cat_%1$s"><b id="b_%1$s">-</b> %2$s</a></li>',
           $c.$_, $self->{categories}{$c}[1]{$_};
         }
         $r .= '</ul>'.($c !~ /[gph]/ ? '</li>' : '');
       }
       $r.'</ul>';
    }],
  ],

  'Image' => [
  ],

  'Relations' => [
  ],

  'Screenshots' => [
  ]);
}


1;

