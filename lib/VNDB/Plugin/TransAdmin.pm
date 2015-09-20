# This plugin provides a quick and dirty user interface to editing lang.txt,
# to use it, add the following to your data/config.pl:
#
#  if($TUWF::OBJ) {
#    TUWF::load('VNDB::Plugin::TransAdmin');
#    $TUWF::OBJ->{transadmin} = {
#      <userid> => 'all' || <language> || <arrayref with languages>
#    };
#  }
#
# And then open /tladmin in your browser.
# Also make sure data/lang.txt and data/docs/* are writable by the httpd process.
# English is considered the 'main' language, and cannot be edited using this interface.

package VNDB::Plugin::TransAdmin;

use strict;
use warnings;
use TUWF ':html', 'uri_escape', 'html_escape';
use LangFile;
use VNDB::Func;


my $langfile = "$VNDB::ROOT/data/lang.txt";


TUWF::register(
  qr{tladmin(?:/([a-z-]+))?} => \&tladmin
);


sub _allowed {
  my($self, $lang) = @_;
  return 0 if !$self->authInfo->{id};
  my $a = $self->{transadmin}{ $self->authInfo->{id} };
  return $a eq 'all' || $a eq $lang || ref($a) eq 'ARRAY' && grep $_ eq $lang, @$a;
}


sub tladmin {
  my($self, $lang) = @_;

  $lang ||= '';
  return $self->resNotFound if $lang && ($lang eq 'en' || !grep $_ eq $lang, $self->{l10n}->languages);
  my $sect = $self->reqGet('sect')||'';
  my $doc = $self->reqGet('doc')||'';

  if(!-w $langfile || !-w "$VNDB::ROOT/data/docs" || grep /\.[a-z]{2}$/ && !-w $_, glob "$VNDB::ROOT/data/docs/*") {
    $self->htmlHeader(title => 'Language file not writable', noindex => 1);
    div class => 'mainbox';
     h1 'Language file not writable';
     div class => 'warning', 'Sorry, I do not have enough permission to write to the language files.';
    end;
    $self->htmlFooter;
    return;
  }

  _savelang($self, $lang) if $lang && $sect && $self->reqMethod eq 'POST' && _allowed($self, $lang);
  _savedoc($self, $lang, $doc) if $lang && $doc && $self->reqMethod eq 'POST' && _allowed($self, $lang);
  my($sects, $page) = _readlang($lang, $sect) if $lang;

  $self->htmlHeader(title => 'Quick-and-dirty Translation Editor', noindex => 1);
  div class => 'mainbox';
   a class => 'addnew', href => '/d17', 'README';
   h1 'Quick-and-dirty Translation Editor';
   h2 class => 'alttitle', 'Step #1: Choose a language';
   p class => 'browseopts';
    a $lang eq $_ ? (class => 'optselected') : (), href => "/tladmin/$_", mt "_lang_$_"
      for grep !/en/, $self->{l10n}->languages;
   end;
   _sections($self, $lang, $sect, $sects) if $lang;
   _docs($lang, $doc) if $lang;
  end;

  _section($self, $lang, $sect, $page) if $lang && $sect;
  _doc($self, $lang, $doc) if $lang && $doc;

  $self->htmlFooter;
}


sub _savelang {
  my($self, $lang) = @_;

  # do everything in-memory, so we don't need write access to a temporary file
  # (this has the downside that in the event something goes wrong, everything will be wiped)
  my $f = LangFile->new(read => $langfile);
  my @read;
  push @read, $_ while (local $_ = $f->read);
  $f->close;

  my @keys = $self->reqPosts;
  $f = LangFile->new(write => $langfile);
  my $key;
  for my $l (@read) {
    $key = $l->[1] if $l->[0] eq 'key';
    if($l->[0] eq 'tl' && $l->[1] eq $lang && grep $key eq $_, @keys) {
      $l->[2] = !$self->reqPost("check$key");
      $l->[3] = $self->reqPost($key);
      $l->[3] =~ s/\r?\n/\n/g;
      $l->[3] =~ s/\s+$//g;
    }
    $f->write(@$l);
  }
  $f->close;

  # re-read the file and regenerate the JS in case we're not running as CGI
  if($INC{"FCGI.pm"}) {
    VNDB::L10N::loadfile();
    system "make -sC $VNDB::ROOT js" if $self->{regen_static};
  }
}


sub _readlang {
  my($lang, $sect) = @_;
  my @sect; # [ title, count, unsync ]
  my @page; # [ 'comment'||'line', <comment>|| ( <key>, <en>, <sync>, <tl> ) ]

  my $f = LangFile->new(read => $langfile);
  my($key, $insect);
  while(my $l = $f->read) {
    my $t = shift @$l;

    if($t eq 'space') {
      if(join("\n", @$l) =~ /((#{30,90}\n)## +(.+) +##\n\2.+)/ms) {
        my $header = $1;
        (my $title = $3) =~ s/\s+$//;
        $title =~ s/\s+\([^)]+\)$//;
        push @sect, [ $title, 0, 0 ];
        $insect = $title eq $sect;
        push @page, [ 'comment', $header ] if $insect;
      } elsif($insect) {
        push @page, [ 'comment', join "\n", @$l ];
      }
    }

    $sect[$#sect][1]++ if $t eq 'key';
    $sect[$#sect][2]++ if $t eq 'tl' && $l->[0] eq $lang && !$l->[1];

    next if !$insect;
    push @page, [ 'line', $l->[0] ] if $t eq 'key';
    $page[$#page][2] = $l->[2] if $t eq 'tl' && $l->[0] eq 'en';
    if($t eq 'tl' && $l->[0] eq $lang) {
      $page[$#page][3] = $l->[1];
      $page[$#page][4] = $l->[2];
    }
  }
  $f->close;
  return (\@sect, \@page);
}


sub _sections {
  my($self, $lang, $sect, $list) = @_;

  br;
  h2 class => 'alttitle', 'Step #2: Choose a section';
  div style => 'margin: 0 40px';
   for (@$list) {
     div style => 'float: left; width: 200px;';
      a href => "/tladmin/$lang?sect=".uri_escape($_->[0]), $_->[0] if $sect ne $_->[0];
      txt $sect if $sect eq $_->[0];
      txt " ";
      txt "0/$_->[1]" if !$_->[2];
      b class => 'standout', "$_->[2]/$_->[1]" if $_->[2];
     end;
   }
   clearfloat;
  end;
  br;
  br;
}


sub _section {
  my($self, $lang, $sect, $page) = @_;

  form action => "/tladmin/$lang?sect=".uri_escape($sect), method => 'POST', 'accept-charset' => 'utf-8';
  div class => 'mainbox';
   h1 $sect;

   if(_allowed($self, $lang)) {
     h2 class => 'alttitle', "Don't forget to hit the 'save' button to make your changes permanent!";
   } else {
     div class => 'warning';
      h2 'Read-only';
      p "You can't edit this language.";
     end;
   }

   my @disabled = _allowed($self, $lang) ? () : (disabled => 'disabled');

   for my $l (@$page) {
     if($l->[0] eq 'comment') {
       pre style => 'padding: 0; margin: 0; background: none; border: none';
        b class => 'grayedout', $l->[1]."\n";
       end;
       next;
     }

     my(undef, $key, $en, $sync, $tl) = @$l;
     b class => $sync ? 'grayedout' : 'standout', ":$key";
     br;
     div style => 'margin-left: 25px; font: 12px Tahoma; width: 700px; overflow-x: auto; white-space: nowrap';
      lit html_escape $en;
     end;
     my $multi = $en =~ y/\n//;

     div style => 'width: 23px; float: left; text-align: right';
      input type => 'checkbox', name => "check$key", id => "check$key", !$sync ? (checked => 'checked') : (), @disabled;
     end;
     div style => 'float: left';
      if($multi) {
        textarea name => $key, id => $key, rows => $multi+2, @disabled,
          style => 'width: 700px; height: auto; white-space: pre; border: none', wrap => 'off', $tl;
      } else {
        input type => 'text', class => 'text', name => $key, id => $key, value => $tl,
          style => 'width: 700px; border: none', @disabled;
      }
     end;
     clearfloat;
   }
   if(_allowed($self, $lang)) {
     br;br;
     fieldset class => 'submit';
      input type => 'submit', value => 'Save', class => 'submit';
     end;
   }
  end;
  end;
}


sub _savedoc {
  my($self, $lang, $doc) = @_;

  my $file = "$VNDB::ROOT/data/docs/$doc.$lang";

  open my $f, '<:utf8', "$VNDB::ROOT/data/docs/$doc" or die $!;
  my $en = join '', <$f>;
  close $f;

  my $tl = $self->reqPost('tl');
  $tl =~ s/\r?\n/\n/g;

  return -e $file && unlink $file if $tl eq $en;

  open $f, '>:utf8', $file or die $!;
  print $f $tl;
  close $f;
  chmod 0666, $file;
}


sub _docs {
  my($lang, $doc) = @_;

  my @d = map /\.[a-z-]{2,5}$/ || /\/(?:8|11|14|17)$/ ? () : s{^.+\/([^/]+)$}{$1} && $_, glob "$VNDB::ROOT/data/docs/*";

  h2 class => 'alttitle', '...or a doc page';
  div style => 'margin: 0 40px';
   for (sort { $a =~ /^\d+$/ && $b =~ /^\d+$/ ? $a <=> $b : $a cmp $b } @d) {
     my $incomplete = 1;
     if(open my $F, '<:utf8', "$VNDB::ROOT/data/docs/$_.$lang") {
       # If there's no ':INC:incomplete' on the first 10 lines, assume the doc page to be fully translated and synced.
       $incomplete = grep +((<$F>||'') =~ /^:INC:incomplete/), 1..10;
     }
     div style => 'float: left; width: 90px;';
      a href => "/tladmin/$lang?doc=$_", $_ if $_ ne $doc;
      txt $_ if $_ eq $doc;
      txt " ";
      b class => 'standout', "!!" if $incomplete;
     end;
   }
   clearfloat;
  end;
}


sub _doc {
  my($self, $lang, $doc) = @_;

  open my $f, '<:utf8', "$VNDB::ROOT/data/docs/$doc" or die $!;
  my $en = join '', <$f>;
  close $f;

  my $tl = $en;
  if(open $f, '<:utf8', "$VNDB::ROOT/data/docs/$doc.$lang") {
    $tl = join '', <$f>;
    close $f;
  }

  form action => "/tladmin/$lang?doc=$doc", method => 'POST', 'accept-charset' => 'utf-8';
  div class => 'mainbox';
   a class => 'addnew', style => 'margin-left: 20px', href => "http://g.blicky.net/vndb.git/log/data/docs/$doc", 'Recent changes';
   a class => 'addnew', href => "/d$doc", "View current page" if $doc =~ /^\d+$/;
   h1 "Translating page $doc";
   h2 class => 'alttitle', 'Left = English, Right = translation';

   if(!_allowed($self, $lang)) {
     div class => 'warning';
      h2 'Read-only';
      p "You can't edit this language.";
     end;
   }

   div style => 'width: 48%; margin-right: 10px; overflow-y: auto; float: left';
    pre style => 'font: 12px Tahoma; border: none; background: none; margin: 0', $en;
   end;
   textarea name => 'tl', id => 'tl', rows => ($en =~ y/\n//), _allowed($self, $lang) ? () : (disabled => 'disabled'),
     style => 'border: none; float: left; width: 49%; white-space: pre', wrap => 'off', $tl;
   clearfloat;
   if(_allowed($self, $lang)) {
     br;
     fieldset class => 'submit';
      input type => 'submit', value => 'Save', class => 'submit';
     end;
   }
  end;
  end;
}


1;

