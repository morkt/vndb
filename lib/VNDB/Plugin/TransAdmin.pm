# This plugin provides a quick and dirty user interface to editing lang.txt,
# to use it, add the following to your data/config.pl:
# 
#  if($INC{"YAWF.pm"}) {
#    require VNDB::Plugin::TransAdmin;
#    $VNDB::S{transadmin} = {
#      <userid> => 'all' || <language> || <arrayref with languages>
#    };
#  }
#
# And then open /tladmin in your browser.
# Also make sure data/lang.txt is writable by the httpd process.
# English is considered the 'main' language, and cannot be edited using this interface.

package VNDB::Plugin::TransAdmin;

use strict;
use warnings;
use YAWF ':html';
use LangFile;
use VNDB::Func;


my $langfile = "$VNDB::ROOT/data/lang.txt";


YAWF::register(
  qr{tladmin(?:/([a-z]+))?} => \&tladmin
);


sub uri_escape {
  local $_ = shift;
  s/ /%20/g;
  s/\?/%3F/g;
  s/;/%3B/g;
  s/&/%26/g;
  return $_;
}


sub _allowed {
  my($self, $lang) = @_;
  my $a = $self->{transadmin}{ $self->authInfo->{id} };
  return $a eq 'all' || $a eq $lang || ref($a) eq 'ARRAY' && grep $_ eq $lang, @$a;
}


sub tladmin {
  my($self, $lang) = @_;

  $lang ||= '';
  return 404 if $lang && ($lang eq 'en' || !grep $_ eq $lang, $self->{l10n}->languages);
  my $sect = $self->reqParam('sect')||'';

  my $uid = $self->authInfo->{id};
  return $self->htmlDenied if !$uid || !$self->{transadmin}{$uid};

  if(!-w $langfile) {
    $self->htmlHeader(title => 'Language file not writable', noindex => 1);
    div class => 'mainbox';
     h1 'Language file not writable';
     div class => 'warning', 'Sorry, I do not have enough permission to write to the language file.';
    end;
    $self->htmlFooter;
    return;
  }

  _savelang($self, $lang) if $lang && $self->reqMethod eq 'POST' && _allowed($self, $lang);
  my($sects, $page) = _readlang($lang, $sect) if $lang;

  $self->htmlHeader(title => 'Quick-and-dirty Translation Editor', noindex => 1);
  div class => 'mainbox';
   h1 'Quick-and-dirty Translation Editor';
   h2 class => 'alttitle', 'Step #1: Choose a language';
   p class => 'browseopts';
    a $lang eq $_ ? (class => 'optselected') : (), href => "/tladmin/$_", mt "_lang_$_"
      for grep !/en/, $self->{l10n}->languages;
   end;
   _sections($self, $lang, $sect, $sects) if $lang;
  end;

  _page($self, $lang, $sect, $page) if $lang && $sect;

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

  my @keys = $self->reqParam;
  $f = LangFile->new(write => $langfile);
  my $key;
  for my $l (@read) {
    $key = $l->[1] if $l->[0] eq 'key';
    if($l->[0] eq 'tl' && $l->[1] eq $lang && grep $key eq $_, @keys) {
      $l->[2] = !$self->reqParam("check$key");
      $l->[3] = $self->reqParam($key);
      $l->[3] =~ s/\r?\n/\n/g;
      $l->[3] =~ s/\s+$//g;
    }
    $f->write(@$l);
  }
  $f->close;

  # re-read the file and regenerate the JS in case we're not running as CGI
  if($INC{"FCGI.pm"}) {
    VNDB::L10N::loadfile();
    VNDB::checkjs();
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
      if(join("\n", @$l) =~ /((#{30,90}\n)## +(.+) +##\n\2.+)^/ms) {
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
}


sub _page {
  my($self, $lang, $sect, $page) = @_;

  form action => "/tladmin/$lang?sect=".uri_escape($sect), method => 'POST', 'accept-charset' => 'utf-8';
  div class => 'mainbox';
   h1 $sect;

   if(_allowed($self, $lang)) {
     h2 class => 'alttitle', "Don't forget to hit the 'save' button to make your changes permament!";
   } else {
     div class => 'warning';
      h2 'Read-only';
      p "You can't edit this language.";
     end;
   }

   for my $l (@$page) {
     if($l->[0] eq 'comment') {
       pre;
        b class => 'grayedout', $l->[1]."\n";
       end;
       next;
     }

     my(undef, $key, $en, $sync, $tl) = @$l;
     b class => $sync ? 'grayedout' : 'standout', ":$key";
     br;
     div style => 'margin-left: 25px; font: 12px Tahoma; width: 700px; overflow-x: auto; white-space: nowrap', $en;
     my $multi = $en =~ y/\n//;

     div style => 'width: 23px; float: left; text-align: right';
      input type => 'checkbox', name => "check$key", id => "check$key", !$sync ? (checked => 'checked') : ();
     end;
     div style => 'float: left';
      if($multi) {
        $tl =~ s/&/&amp;/;
        $tl =~ s/</&lt;/;
        $tl =~ s/>/&gt;/;
        textarea name => $key, id => $key, rows => $multi+2, style => 'width: 700px; height: auto; white-space: nowrap; border: none', wrap => 'off';
         lit $tl;
        end;
      } else {
        input type => 'text', class => 'text', name => $key, id => $key, value => $tl, style => 'width: 700px; border: none';
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


1;

