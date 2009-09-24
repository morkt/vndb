
package VNDB::Util::LayoutHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';
use VNDB::Func;

our @EXPORT = qw|htmlHeader htmlFooter|;


sub htmlHeader { # %options->{ title, js, noindex, search }
  my($self, %o) = @_;
  my $skin = $self->reqParam('skin') || $self->authInfo->{skin} || $self->{skin_default};
  $skin = $self->{skin_default} if !$self->{skins}{$skin} || !-d "$VNDB::ROOT/static/s/$skin";

  # heading
  html;
   head;
    title $o{title};
    Link rel => 'shortcut icon', href => '/favicon.ico', type => 'image/x-icon';
    Link rel => 'stylesheet', href => $self->{url_static}.'/s/'.$skin.'/style.css?'.$self->{version}, type => 'text/css', media => 'all';
    Link rel => 'search', type => 'application/opensearchdescription+xml', title => 'VNDB VN Search', href => $self->{url}.'/opensearch.xml';
    if($o{js}) {
      script type => 'text/javascript', src => $self->{url_static}.'/f/forms.js?'.$self->{version}; end;
    }
    script type => 'text/javascript', src => $self->{url_static}.'/f/script.js?'.$self->{version};
     # most browsers don't like a self-closing <script> tag...
    end;
    if($self->authInfo->{customcss}) {
      (my $css = $self->authInfo->{customcss}) =~ s/\n/ /g;
      style type => 'text/css', $css;
    }
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
     span;
      for (grep $self->{l10n}->language_tag() ne $_, $self->{l10n}->languages()) {
        a href => "?l10n=$_";
         cssicon "lang $_", mt "_lang_$_"; # NOTE: should actually be in the destination language...
        end;
      }
     end;
     txt mt '_menu';
    end;
    div;
     a href => '/',      mt '_menu_home'; br;
     a href => '/v/all', mt '_menu_vn'; br;
     a href => '/r',     mt '_menu_releases'; br;
     a href => '/p/all', mt '_menu_producers'; br;
     a href => '/g',     mt '_menu_tags'; br;
     a href => '/u/all', mt '_menu_users'; br;
     a href => '/hist',  mt '_menu_recent_changes'; br;
     a href => '/t',     mt '_menu_discussion_board'; br;
     a href => '/d6',    mt '_menu_faq'; br;
     a href => '/v/rand', mt '_menu_randvn'; br;
     a href => 'irc://irc.synirc.net/vndb', '#vndb';
      lit ' (<a href="http://cgiirc.synirc.net/?chan=%23vndb">'.mt('_menu_webchat').'</a>)';
    end;
    form action => '/v/all', method => 'get', id => 'search';
     fieldset;
      legend 'Search';
      input type => 'text', class => 'text', id => 'sq', name => 'sq', value => $o{search}||mt('_menu_emptysearch');
      input type => 'submit', class => 'submit', value => 'Search';
     end;
    end;
   end;

   div class => 'menubox';
    if($self->authInfo->{id}) {
      my $uid = sprintf '/u%d', $self->authInfo->{id};
      h2;
       a href => $uid, ucfirst $self->authInfo->{username};
       # note: user ranks aren't TL'ed (but might be in the future, hmm)
       txt ' ('.mt('_urank_'.$self->authInfo->{rank}).')';
      end;
      div;
       a href => "$uid/edit", mt '_menu_myprofile'; br;
       a href => "$uid/list", mt '_menu_myvnlist'; br;
       a href => "$uid/wish", mt '_menu_mywishlist'; br;
       a href => "/t$uid",    mt '_menu_mymessages', $self->authInfo->{mymessages}; br;
       a href => "$uid/hist", mt '_menu_mychanges'; br;
       a href => "$uid/tags", mt '_menu_mytags'; br;
       br;
       a href => '/v/new',    mt '_menu_addvn'; br;
       a href => '/p/new',    mt '_menu_addproducer'; br;
       br;
       a href => '/u/logout', mt '_menu_logout';
      end;
    } else {
      h2;
       a href => '/u/login', mt '_menu_login';
      end;
      div;
       form action => '/nospam?/u/login', id => 'loginform', method => 'post';
        fieldset;
         legend 'Login';
         input type => 'text', class => 'text', id => 'username', name => 'usrname';
         input type => 'password', class => 'text', id => 'userpass', name => 'usrpass';
         input type => 'submit', class => 'submit', value => mt '_menu_login';
        end;
       end;
       p;
        lit mt '_menu_loginmsg', '/u/register', '/u/newpass';
       end;
      end;
    }
   end;

   div class => 'menubox';
    h2 mt '_menu_dbstats';
    div;
     dl;
      for (qw|vn releases producers users threads posts|) {
        dt mt "_menu_stat_$_";
        dd $self->{stats}{$_};
      }
     end;
     clearfloat;
    end;
   end;
  end;
}


sub htmlFooter {
  my $self = shift;
     div id => 'footer';

      my $q = $self->dbRandomQuote;
      if($q && $q->{vid}) {
        lit '"';
        a href => "/v$q->{vid}", style => 'text-decoration: none', $q->{quote};
        txt qq|"\n|;
      }

      txt "vndb $self->{version} | ";
      a href => '/d7', mt '_footer_aboutus';
      txt ' | ';
      a href => "mailto:$self->{admin_email}", $self->{admin_email};
      txt ' | ';
      a href => $self->{source_url}, mt '_footer_source';
     end;
    end; # /div maincontent
   end; # /body
  end; # /html

  # write the SQL queries as a HTML comment when debugging is enabled
  if($self->debug) {
    lit "\n<!--\n SQL Queries:\n";
    for (@{$self->{_YAWF}{DB}{queries}}) {
      my $q = !ref $_->[0] ? $_->[0] :
        $_->[0][0].(exists $_->[0][1] ? ' | "'.join('", "', map defined()?$_:'NULL', @{$_->[0]}[1..$#{$_->[0]}]).'"' : '');
      $q =~ s/^\s//g;
      lit sprintf "  [%6.2fms] %s\n", $_->[1]*1000, $q;
    }
    lit "-->\n";
  }
}


1;
