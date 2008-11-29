
package VNDB::Util::LayoutHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';

our @EXPORT = qw|htmlHeader htmlFooter|;


sub htmlHeader { # %options->{ title }
  my($self, %o) = @_;

  # heading
  html;
   head;
    title $o{title};
    Link rel => 'shortcut icon', href => '/favicon.ico', type => 'image/x-icon';
    Link rel => 'stylesheet', href => $self->{url_static}.'/f/style.css', type => 'text/css', media => 'all';
    if($o{js}) {
      script type => 'text/javascript', src => $self->{url_static}.'/f/forms.js'; end;
    }
    script type => 'text/javascript', src => $self->{url_static}.'/f/script.js';
     # most browsers don't like a self-closing <script> tag...
    end;
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
  my $self = shift;

  div id => 'menulist';

   div class => 'menubox';
    h2 'Menu';
    div;
     for (
       [ '/'   => 'Home'              ],
       [ '#'   => 'Visual Novels'     ],
       [ '/p/all'  => 'Producers'     ],
       [ '/u/list/all' => 'Users'     ],
       [ '/hist' => 'Recent Changes'    ],
       [ '/t'   => 'Discussion Board'  ],
       [ '#'   => 'FAQ'               ]) {
       a href => $$_[0], $$_[1];
       br;
     }
    end;
   end;

   div class => 'menubox';
    if($self->authInfo->{id}) {
      my $uid = sprintf '/u%d', $self->authInfo->{id};
      h2;
       a href => $uid, ucfirst $self->authInfo->{username};
       txt ' ('.$self->{user_ranks}[$self->authInfo->{rank}][0].')';
      end;
      div;
       a href => "$uid/edit", 'My Profile'; br;
       a href => "$uid/list", 'My Visual Novel List'; br;
       a href => "$uid/wish", 'My Wishlist'; br;
       a href => "/t$uid",    'My Messages'; br;
       a href => "$uid/hist", 'My Recent Changes'; br;
       br;
       a href => '/v/new',    'Add Visual Novel'; br;
       a href => '/p/new',    'Add Producer'; br;
       br;
       a href => '/u/logout', 'Logout';
      end;
    } else {
      h2;
       a href => '/u/login', 'Login';
      end;
      div;
       form action => '/nospam?/u/login', id => 'loginform', method => 'post';
        fieldset;
         legend 'Login';
         input type => 'text', class => 'text', id => 'username', name => 'usrname';
         input type => 'password', class => 'text', id => 'userpass', name => 'usrpass';
         input type => 'submit', class => 'submit', value => 'Login';
        end;
       end;
       p;
        lit 'Need to <a href="/u/register">register</a>,<br />';
        lit 'or <a href="/u/newpass">forgot your password?</a>';
       end;
      end;
    }
   end;

   my @stats = (
     [ vn        => 'Visual Novels' ],
     [ releases  => 'Releases'      ],
     [ producers => 'Producers'     ],
     [ users     => 'Users'         ],
     [ threads   => 'Threads'       ],
     [ posts     => 'Posts'         ],
   );
   my $stats = $self->dbStats;
   div class => 'menubox';
    h2 'Database Statistics';
    div;
     dl;
      for (@stats) {
        dt $$_[1];
        dd $stats->{$$_[0]};
      }
     end;
     br style => 'clear: left';
    end;
   end;
  end;
}


sub htmlFooter {
  my $self = shift;
    end; # /div maincontent
   end; # /body
  end; # /html

  # write the SQL queries as a HTML comment when debugging is enabled
  if($self->debug) {
    lit "\n<!--\n SQL Queries:\n";
    for (@{$self->{_YAWF}{DB}{queries}}) {
      my $q = !ref $_->[0] ? $_->[0] :
        $_->[0][0].(exists $_->[0][1] ? ' | "'.join('", "', @{$_->[0]}[1..$#{$_->[0]}]).'"' : '');
      $q =~ s/^\s//g;
      lit sprintf "  [%6.2fms] %s\n", $_->[1]*1000, $q;
    }
    lit "-->\n";
  }
}


1;
