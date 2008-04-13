# VNDB::Util::Template - A direct copy of NTL::Util::Template

# This file has not been edited for at least a year,
# and there's probably no need to do so in the near future

# template specific stuff:
#  [[ perl code to execute at the specified place ]]
#  [[= perl code, append return value to the template at the specified place ]]
#  [[: same as above, but escape special HTML chars (<, >, &, " and \n) ]]
#  [[% same as above, but also escape as an URL (expects UTF-8 strings) ]]
#  [[! perl code, append at the top of the script (useful for subroutine-declarations etc) ]]
#  [[+ path to a file to include, relative to $searchdir ]]

package VNDB::Util::Template;

use strict;
use warnings;

use vars ('$VERSION', '@EXPORT');
$VERSION = $VNDB::VERSION;


sub new {
  my $pack = shift;
  my %ops = @_;
  my $me = bless { 
    namespace     => __PACKAGE__ . '::tpl',
    pre_chomp     => 0,
    post_chomp    => 0,
    rm_newlines   => 0,
    %ops,
    lastreload    => 0
  }, ref($pack) || $pack;

  $me->{mainfile} = sprintf '%s/%s', $me->{searchdir}, $me->{filename};

  die "No filename specified!" if !$me->{filename};
  die "No searchdir specified!" if !$me->{searchdir};
  die "Filename does not exist!" if !-e $me->{mainfile};
  die "No place for the compiled script specified!" if !$me->{compiled};

  $me->includescript();

  return $me;
}

sub includescript {
  my $self = shift;

  my $dt = 0;
  my $dc = (stat($self->{compiled}))[9] || 0;

  if(-s $self->{compiled} && !exists $INC{$self->{compiled}}) {
    eval { require $self->{compiled}; };
    if(!$@) {
      $self->{lastreload} = $dc;
    } else {
     # make sure we can fix the problem and try again
      $INC{$self->{compiled}} = $self->{compiled};
      die $@;
    }
  }

  my $T_version = eval(sprintf '$%s::VERSION;', $self->{namespace});

  if($dc > $self->{lastreload} || !$T_version) {
    $dt = 1;
  }
  elsif($self->{deep_reload} && $T_version >= 0.1) {
    my @T_files = @{ eval(sprintf '\@%s::T_FILES;', $self->{namespace}) };
    if($#T_files >= 0) {
      foreach (@T_files) {
        if((stat(sprintf('%s/%s', $self->{searchdir}, $_)))[9] > $dc) {
          $dt = 2;
          last;
        }
      } 
    }
  } elsif((stat($self->{mainfile}))[9] > $dc) {
    $dt = 2;
  }
  if($dt) {
    $self->compiletpl() if $dt == 2 || $dc <= $self->{lastreload};
    delete $INC{$self->{compiled}};
    eval { require $self->{compiled}; };
    if(!$@) {
      warn "Reloaded template\n";
    } else {
      $INC{$self->{compiled}} = $self->{compiled};
      warn "Template contains errors, not reloading\n";
    }
    $self->{lastreload} = (stat($self->{compiled}))[9];
  }
}

sub compile {
  my $self = shift;
  my $X = shift;
  $self->includescript();

  return $self->{namespace}->compile($X);
}

sub compiletpl {
  my $self = shift;
  open(my $T, '>', $self->{compiled}) || die sprintf '%s: %s', $self->{compiled}, $!;
  printf $T <<__, __PACKAGE__, $self->{namespace}, ($self->compilefile());
# Compiled from a template by %s
package %s;

use strict;
use warnings;
no warnings qw(redefine);
use URI::Escape \'uri_escape_utf8\';

our \$VERSION = 0.1;
our \@T_FILES = qw| %s |;

sub _hchar { local\$_=shift||return\'\';s/&/&amp;/g;s/</&lt;/g;s/>/&gt;/g;s/"/&quot;/g;s/\\r?\\n/<br \\/>/g;return\$_; }
sub _huri  { _hchar(uri_escape_utf8((scalar shift)||return \'\')) }
%s
%s
%s
1;
__
  close($T);
  warn "Recompiled template\n";
}

sub compilefile {
  my $self = shift;
  my $file = shift||$self->{filename};
  my $func = shift||'compile';

  my $files = $file;
  $file = sprintf('%s/%s', $self->{searchdir}, $file);
  open(my $F, '<', $file) || die "$file: $!";
  my $tpl = '';
  $tpl .= $_ while(<$F>);
  close($F);
  my @t = split(//, $tpl);
  $tpl = undef;

  my $inperl = 0;
  my $top = '';
  my $R = '';
  my $bottom = '';
  my $dat = '';
  my $perl = '';

  for(my $i=0; $i<=$#t; $i++) {
  # [[= (2), [[: (3) and [[% (4)
    if(!$inperl && $t[$i] eq '[' && $t[$i+1] eq '[' && $t[$i+2] =~ /[=:%]/) {
      $i+=2;
      if($t[$i] eq '=') {
        $inperl=2;
        $perl = '\' . ( scalar ';
      } elsif($t[$i] eq ':') {
        $inperl=3;
        $perl = '\' . _hchar( scalar ';
      } else {
        $inperl=4;
        $perl = '\' . _huri( scalar ';
      }
      $R .= $self->_pd($dat);
    } elsif($inperl >= 2 && $inperl <= 4 && $t[$i] eq ']' && $t[$i+1] eq ']') {
      $inperl=0; $i++;
      $R .= $perl . "\n) . '";
      $dat = '';
  # [[! (5)
    } elsif(!$inperl && $t[$i] eq '[' && $t[$i+1] eq '[' && $t[$i+2] eq '!') {
      $inperl=5; $i+=2;
      $perl = '';
      $R .= $self->_pd($dat);
    } elsif($inperl == 5 && $t[$i] eq ']' && $t[$i+1] eq ']') {
      $inperl=0; $i++;
      $top .= $perl . "\n";
      $dat = '';
  # [[+ (6)
    } elsif(!$inperl && $t[$i] eq '[' && $t[$i+1] eq '[' && $t[$i+2] eq '+') {
      $inperl=6; $i+=2;
      $R .= $self->_pd($dat);
      $perl = '';
    } elsif($inperl == 6 && $t[$i] eq ']' && $t[$i+1] eq ']') {
      $inperl=0;$i++;
      $perl =~ s/[\r\n\s]//g;
      die "Invalid file specified: $perl\n" if $perl !~ /^[a-zA-Z0-9-_\.\/]+$/;
      (my $func = $perl) =~ s/[^a-zA-Z0-9_]/_/g;
      my($ifiles, $itop, $imid, $ibot) = $self->compilefile($perl, "T_$func");
      $files .= ' ' . $ifiles;
      $top .= $itop;
      $bottom .= "\n\n$imid\n$ibot\n";
      $R .= "' . T_$func(\$X) . '";
      $dat = '';     
  # [[ (1)
    } elsif(!$inperl && $t[$i] eq '[' && $t[$i+1] eq '[') {
      $inperl = 1; $i++;
      $R .= $self->_pd($dat);
      $perl = "';\n";
    } elsif($inperl == 1 && $t[$i] eq ']' && $t[$i+1] eq ']') {
      $inperl=0; $i++;
      $R .= $perl . "\n \$R .= '";
      $dat = '';
  # data
    } elsif(!$inperl) { 
      (my $l = $t[$i]) =~ s/'/\\'/;
      $dat .= $l;
    } else {
      $perl .= $t[$i];
    }
  }
  if(!$inperl) {
    $R .= $self->_pd($dat) . "';\n";
  } else {
    die "Error, no ']]' found at $file!\n";
  }
  $R = "sub $func {
    my \$X = \$_[". ($func eq 'compile' ? 1 : 0) . "];
    my \$R = '".$R."
    return \$R;
  }";
  return($files, $top, $R, $bottom);
}

sub _pd { # Parse Dat
  my $self = shift;
  local $_ = shift;

  s/[\r\n\s]+$//g if $_ !~ s/-$// && $self->{pre_chomp};
  s/^[\r\n\s]+//g if $_ !~ s/^-// && $self->{post_chomp};
  s/([\s\t]*)[\r\n]+([\s\t]*)/{ $1||$2?' ':'' }/eg if $self->{rm_newlines};
  return $_;
}

1;
