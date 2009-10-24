

package LangFile;

use strict;
use warnings;
use Fcntl qw(LOCK_SH LOCK_EX SEEK_SET);


sub new {
  my($class, $action, $file) = @_;
  open my $F, $action eq 'read' ? '<:utf8' : '>:utf8', $file or die "Opening $file: $!";
  flock($F, $action eq 'read' ? LOCK_SH : LOCK_EX) or die "Locking $file: $!";
  seek($F, 0, SEEK_SET) or die "Seeking $file: $!";
  return bless {
    act => $action,
    FH => $F,
    # status vars for reading
    intro => 1,
    last => [],
  }, $class;
}


sub read {
  my $self = shift;
  my $FH = $self->{FH};
  my @lines;
  my $state = '';
  my($lang, $sync);

  while((my $l = shift(@{$self->{last}}) || <$FH>)) {
    $l =~ s/[\r\n\t\s]+$//;

    # header
    if($self->{intro}) {
      push @lines, $l;
      next if $l ne '/intro';
      $self->{intro} = 0;
      return [ 'space', @lines ];
    }

    # key
    if(!$state && $l =~ /^:(.+)$/) {
      return [ 'key', $1 ];
    }

    # space
    if((!$state || $state eq 'space') && ($l =~ /^#/ || $l eq '')) {
      $state = 'space';
      push @lines, $l;
    } elsif($state eq 'space') {
      push @{$self->{last}}, "$l\n";
      return [ 'space', @lines ];
    }

    # tl
    if(!$state && $l =~ /^([a-z_-]{2})([ *]):(?: (.+)|)$/) {
      $lang = $1;
      $sync = $2 eq '*' ? 0 : 1;
      push @lines, $3||'';
      $state = 'tl';
    } elsif($state eq 'tl' && $l =~ /^\s{5}(.+)$/) {
      push @lines, $1;
    } elsif($state eq 'tl' && $l eq '') {
      push @lines, $l;
    } elsif($state eq 'tl') {
      my $trans = join "\n", @lines;
      push @{$self->{last}}, "\n" while $trans =~ s/\n$//;
      push @{$self->{last}}, $l;
      return [ 'tl', $lang, $sync, $trans ];
    }

    die "Don\'t know what to do with \"$l\"" if !$state;
  }
  if($state eq 'space') {
    return [ 'space', @lines ];
  }
  if($state eq 'tl') {
    my $trans = join "\n", @lines;
    push @{$self->{last}}, "\n" while $trans =~ s/\n$//;
    return [ 'tl', $lang, $sync, $trans ];
  }
  return undef;
}


sub write {
  my($self, @line) = @_;
  my $FH = $self->{FH};

  my $t = shift @line;

  if($t eq 'space') {
    print $FH "$_\n" for @line;
  }

  if($t eq 'key') {
    print $FH ":$line[0]\n";
  }

  if($t eq 'tl') {
    my($lang, $sync, $text) = @line;
    $text =~ s/\n([^\n])/\n     $1/g;
    $text = " $text" if $text ne '';
    printf $FH "%s%s:%s\n", $lang, $sync ? ' ' : '*', $text;
  }
}


sub close {
  my $self = shift;
  close $self->{FH};
}

1;

__END__
=pod

=head1 NAME

LangFile - Simple object oriented interface for the parsing and creation of lang.txt

=head1 USAGE

  use LangFile;
  my $read = LangFile->new(read => "data/lang.txt");
  my $write = LangFile->new(write => "lang-copy.txt");

  while((my $line = $read->read())) {
    # $line is an arrayref in one of the following formats:
    # [ 'space', @lines ]
    #   unparsed lines, like the header, newlines and comments
    # [ 'key', $key ]
    #   key line, $key is key name
    # [ 'tl', $lang, $sync, $text ]
    #   translation line(s), $lang = language tag, $sync = 1/0, $text = translation (can include newlines)
    # $line is undef on EOF, $read->next() die()s on a parsing error

    # create an identical copy of $read in $write
    $write->write(@$line);
  }
  $write->close;

