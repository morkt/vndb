
package VNDB::Handler::VNEdit;

use strict;
use warnings;
use YAWF ':html';


YAWF::register(
  qr{v([1-9]\d*)/edit},   \&edit,
);


sub edit {
  my($self, $vid) = @_;

  my $v = $self->dbVNGet(id => $vid, what => 'extended screenshots relations anime categories changes')->[0];
  return 404 if !$v->{id};

  return $self->htmlDenied if !$self->authCan('edit')
    || ($v->{locked} && !$self->authCan('lock') || $v->{hidden} && !$self->authCan('del'));

  my $frm;

  $self->htmlHeader(title => 'Edit '.$v->{title});
  $self->htmlMainTabs('v', $v, 'edit');
  $self->htmlEditMessage('v', $v);
  _form($self, $v, $frm);
  $self->htmlFooter;
}


sub _form {
  my($self, $v, $frm) = @_;
  $self->htmlForm({ frm => $frm, action => "/v$v->{id}/edit", editsum => 1 },
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
  ],

  'Image' => [
  ],

  'Relations' => [
  ],

  'Screenshots' => [
  ]);
}


1;

