
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
  tag 'html', lang => $self->{l10n}->language_tag();
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
      a href => '/', lc mt '_site_title';
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
     a href => "#", id => 'lang_select';
      cssicon "lang ".$self->{l10n}->language_tag(), mt "_lang_".$self->{l10n}->language_tag();
     end;
     txt mt '_menu';
    end;
    div;
     a href => '/',      mt '_menu_home'; br;
     a href => '/v/all', mt '_menu_vn'; br;
     b class => 'grayedout', '> '; a href => '/g', mt '_menu_tags'; br;
     a href => '/r',     mt '_menu_releases'; br;
     a href => '/p/all', mt '_menu_producers'; br;
     a href => '/s/all', mt '_menu_staff'; br;
     a href => '/c/all', mt '_menu_characters'; br;
     b class => 'grayedout', '> '; a href => '/i', mt '_menu_traits'; br;
     a href => '/u/all', mt '_menu_users'; br;
     a href => '/hist',  mt '_menu_recent_changes'; br;
     a href => '/t',     mt '_menu_discussion_board'; br;
     a href => '/d6',    mt '_menu_faq'; br;
     a href => '/v/rand', mt '_menu_randvn';
    end;
    form action => '/v/all', method => 'get', id => 'search';
     fieldset;
      legend 'Search';
      input type => 'text', class => 'text', id => 'sq', name => 'sq', value => $o{search}||'', placeholder => mt('_menu_emptysearch');
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
       a href => "$uid/edit", mt '_menu_myprofile'; br;
       a href => "$uid/list", mt '_menu_myvnlist'; br;
       a href => "$uid/votes",mt '_menu_myvotes'; br;
       a href => "$uid/wish", mt '_menu_mywishlist'; br;
       a href => "$uid/notifies", $nc ? (class => 'notifyget') : (), mt('_menu_mynotifications').($nc?" ($nc)":''); br;
       a href => "$uid/hist", mt '_menu_mychanges'; br;
       a href => '/g/links?u='.$self->authInfo->{id}, mt '_menu_mytags'; br;
       br;
       if($self->authCan('edit')) {
         a href => '/v/add',    mt '_menu_addvn'; br;
         a href => '/p/new',    mt '_menu_addproducer'; br;
         a href => '/s/new',    mt '_menu_addstaff'; br;
         a href => '/c/new',    mt '_menu_addcharacter'; br;
       }
       br;
       a href => "$uid/logout", mt '_menu_logout';
      end;
    } else {
      h2 mt '_menu_user';
      div;
       my $ref = uri_escape $self->reqPath().$self->reqQuery();
       a href => "/u/login?ref=$ref", mt '_menu_login'; br;
       a href => '/u/newpass', mt '_menu_newpass'; br;
       a href => '/u/register', mt '_menu_register'; br;
      end;
    }
   end 'div'; # /menubox

   div class => 'menubox';
    h2 mt '_menu_dbstats';
    div;
     dl;
      for (qw|vn releases producers chars staff tags traits users threads posts|) {
        dt mt "_menu_stat_$_";
        dd $self->{stats}{$_};
      }
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
      a href => '/d7', mt '_footer_aboutus';
      txt ' | ';
      a href => 'irc://irc.synirc.net/vndb', '#vndb';
      txt ' | ';
      a href => "mailto:$self->{admin_email}", $self->{admin_email};
      txt ' | ';
      a href => $self->{source_url}, mt '_footer_source';
     end;
    end 'div'; # /maincontent

    # Abuse an empty noscript tag for the formcode to update a preference setting, if the page requires one.
    noscript id => 'pref_code', title => $self->authGetCode('/xml/prefs.xml'), ''
      if $o{pref_code} && $self->authInfo->{id};
    script type => 'text/javascript', src => $self->{url_static}.'/f/js/'.$self->{l10n}->language_tag().'.js?'.$self->{version}, '';
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
