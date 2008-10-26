
package VNDB::Util::CommonHTML;

use strict;
use warnings;
use YAWF ':html';
use Exporter 'import';

our @EXPORT = qw|
  htmlHeader htmlFooter
|;


sub htmlHeader { # %options->{ title }
  my($self, %o) = @_;

  # heading
  html;
   head;
    title $o{title};
    Link rel => 'shortcut icon', href => '/favicon.ico', type => 'image/x-icon';
    Link rel => 'stylesheet', href => $self->{url_static}.'/f/style.css', type => 'text/css', media => 'all';
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
  div id => 'menulist';

   div class => 'menubox';
    h2 'Menu';
    div;
     for (
       [ '/'   => 'Home'              ],
       [ '#'   => 'Visual Novels'     ],
       [ '#'   => 'Producers'         ],
       [ '#'   => 'Users'             ],
       [ '#'   => 'Recent Changes'    ],
       [ '#'   => 'Discussion Board'  ],
       [ '#'   => 'FAQ'               ]) {
       a href => $$_[0], $$_[1];
       br;
     }
    end;
   end;

   # show user or login menubox here

   # these stats are fake, need to be fetched from the DB
   div class => 'menubox';
    h2 'Database Statistics';
    div;
     dl;
      dt 'Visual Novels';
      dd 1232;
      dt 'Releases';    
      dd 3940;
      dt 'Producers';
      dd 643;
      dt 'Users';
      dd 769;
     end;
     br style => 'clear: left';
    end;
   end;
  end;
}


sub htmlFooter {
    end; # /div maincontent
   end; # /body
  end; # /html
}

1;
