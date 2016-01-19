
package VNDB::Util::LayoutHTML;

use strict;
use warnings;
use TUWF ':html', 'uri_escape';
use Exporter 'import';
use Encode 'decode_utf8';
use VNDB::Func;

our @EXPORT = qw|htmlHeader htmlFooter|;


sub htmlHeader { # %options->{ title, noindex, search, feeds, svg }
  my($self, %o) = @_;
  my $skin = $self->reqGet('skin') || $self->authPref('skin') || $self->{skin_default};
  $skin = $self->{skin_default} if !$self->{skins}{$skin} || !-d "$VNDB::ROOT/static/s/$skin";

  # heading
  lit '<!DOCTYPE HTML>';
  tag 'html', lang => 'en';
   head;
    title $o{title};
    Link rel => 'shortcut icon', href => '/favicon.ico', type => 'image/x-icon';
    Link rel => 'stylesheet', href => $self->{url_static}.'/s/'.$skin.'/style.css?'.$self->{version}, type => 'text/css', media => 'all';
    Link rel => 'search', type => 'application/opensearchdescription+xml', title => 'VNDB VN Search', href => $self->reqBaseURI().'/opensearch.xml';
    if($self->authPref('customcss')) {
      (my $css = $self->authPref('customcss')) =~ s/\n/ /g;
      style type => 'text/css', $css;
    }
    Link rel => 'alternate', type => 'application/atom+xml', href => "/feeds/$_.atom", title => $self->{atom_feeds}{$_}[1]
      for ($o{feeds} ? @{$o{feeds}} : ());
    meta name => 'robots', content => 'noindex, follow', undef if $o{noindex};
   end;
   body;
    div id => 'bgright', ' ';
    div id => 'header';
     h1;
      a href => '/', 'the visual novel database';
     end;
    end;

    _menu($self, %o);

    div id => 'maincontent';
}


sub _menu {
  my($self, %o) = @_;

  div id => 'menulist';

   div class => 'menubox';
    h2;
     txt 'Menu';
    end;
    div;
     a href => '/',      'Home'; br;
     a href => '/v/all', 'Visual novels'; br;
     b class => 'grayedout', '> '; a href => '/g', 'Tags'; br;
     a href => '/r',     'Releases'; br;
     a href => '/p/all', 'Producers'; br;
     a href => '/s/all', 'Staff'; br;
     a href => '/c/all', 'Characters'; br;
     b class => 'grayedout', '> '; a href => '/i', 'Traits'; br;
     a href => '/u/all', 'Users'; br;
     a href => '/hist',  'Recent changes'; br;
     a href => '/t',     'Discussion board'; br;
     a href => '/d6',    'FAQ'; br;
     a href => '/v/rand','Random visual novel';
    end;
    form action => '/v/all', method => 'get', id => 'search';
     fieldset;
      legend 'Search';
      input type => 'text', class => 'text', id => 'sq', name => 'sq', value => $o{search}||'', placeholder => 'search';
      input type => 'submit', class => 'submit', value => 'Search';
     end;
    end;
   end 'div'; # /menubox

   div class => 'menubox';
    if($self->authInfo->{id}) {
      my $uid = sprintf '/u%d', $self->authInfo->{id};
      my $nc = $self->authInfo->{notifycount};
      h2;
       a href => $uid, ucfirst $self->authInfo->{username};
      end;
      div;
       a href => "$uid/edit", 'My Profile'; br;
       a href => "$uid/list", 'My Visual Novel List'; br;
       a href => "$uid/votes",'My Votes'; br;
       a href => "$uid/wish", 'My Wishlist'; br;
       a href => "$uid/notifies", $nc ? (class => 'notifyget') : (), 'My Notifications'.($nc?" ($nc)":''); br;
       a href => "$uid/hist", 'My Recent Changes'; br;
       a href => '/g/links?u='.$self->authInfo->{id}, 'My Tags'; br;
       br;
       if($self->authCan('edit')) {
         a href => '/v/add',    'Add Visual Novel'; br;
         a href => '/p/new',    'Add Producer'; br;
         a href => '/s/new',    'Add Staff'; br;
         a href => '/c/new',    'Add Character'; br;
       }
       br;
       a href => "$uid/logout", 'Logout';
      end;
    } else {
      h2 'User menu';
      div;
       my $ref = uri_escape $self->reqPath().$self->reqQuery();
       a href => "/u/login?ref=$ref", 'Login'; br;
       a href => '/u/newpass', 'Password reset'; br;
       a href => '/u/register', 'Register'; br;
      end;
    }
   end 'div'; # /menubox

   div class => 'menubox';
    h2 'Database Statistics';
    div;
     dl;
      dt 'Visual Novels';   dd $self->{stats}{vn};
      dt 'Releases';        dd $self->{stats}{releases};
      dt 'Producers';       dd $self->{stats}{producers};
      dt 'Characters';      dd $self->{stats}{chars};
      dt 'Staff';           dd $self->{stats}{staff};
      dt 'VN Tags';         dd $self->{stats}{tags};
      dt 'Character Traits';dd $self->{stats}{traits};
      dt 'Users';           dd $self->{stats}{users};
      dt 'Threads';         dd $self->{stats}{threads};
      dt 'Posts';           dd $self->{stats}{posts};
     end;
     clearfloat;
    end;
   end;
  end 'div'; # /menulist
}


sub htmlFooter { # %options => { pref_code => 1 }
  my($self, %o) = @_;
     div id => 'footer';

      my $q = $self->dbRandomQuote;
      if($q && $q->{vid}) {
        lit '"';
        a href => "/v$q->{vid}", style => 'text-decoration: none', $q->{quote};
        txt '"';
        br;
      }

      txt "vndb $self->{version} | ";
      a href => '/d7', 'about us';
      txt ' | ';
      a href => 'irc://irc.synirc.net/vndb', '#vndb';
      txt ' | ';
      a href => "mailto:$self->{admin_email}", $self->{admin_email};
      txt ' | ';
      a href => $self->{source_url}, 'source';
     end;
    end 'div'; # /maincontent

    # Abuse an empty noscript tag for the formcode to update a preference setting, if the page requires one.
    noscript id => 'pref_code', title => $self->authGetCode('/xml/prefs.xml'), ''
      if $o{pref_code} && $self->authInfo->{id};
    script type => 'text/javascript', src => $self->{url_static}.'/f/vndb.js?'.$self->{version}, '';
   end 'body';
  end 'html';

  # write the SQL queries as a HTML comment when debugging is enabled
  if($self->debug) {
    lit "\n<!--\n SQL Queries:\n";
    for (@{$self->{_TUWF}{DB}{queries}}) {
      my $q = !ref $_->[0] ? $_->[0] :
        $_->[0][0].(exists $_->[0][1] ? ' | "'.join('", "', map defined()?$_:'NULL', @{$_->[0]}[1..$#{$_->[0]}]).'"' : '');
      $q =~ s/^\s//g;
      lit sprintf "  [%6.2fms] %s\n", $_->[1]*1000, $q;
    }
    lit "-->\n";
  }
}


1;
