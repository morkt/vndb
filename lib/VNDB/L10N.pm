
use strict;
use warnings;

{
  package VNDB::L10N;
  use base 'Locale::Maketext';

  sub fallback_languages { ('en') };

  # used for the language switch interface, language tags must
  # be the same as in the languages hash in global.pl
  sub languages { ('en', 'ru') }

  # can be called as either a subroutine or a method
  sub loadfile {
    my %lang = (
      en => \%VNDB::L10N::en::Lexicon,
      ru => \%VNDB::L10N::ru::Lexicon,
    );

    open my $F, '<:utf8', $VNDB::ROOT.'/data/lang.txt' or die "Opening language file: $!\n";
    my($empty, $line, $key, $lang) = (0, 0);
    while(<$F>) {
      chomp;
      $line++;

      # ignore intro
      if(!defined $key) {
        $key = 0 if /^\/intro$/;
        next;
      }
      # ignore comments
      next if /^#/;
      # key
      if(/^:(.+)$/) {
        $key = $1;
        $lang = undef;
        $empty = 0;
        next;
      }
      # locale string
      if(/^([a-z_-]{2,7})[ *]: (.+)$/) {
        $lang = $1;
        die "Unknown language on #$line: $lang\n" if !$lang{$lang};
        die "Unknown key for locale on #$line\n" if !$key;
        $lang{$lang}{$key} = $2;
        $empty = 0;
        next;
      }
      # multi-line locale string
      if($lang && /^\s+([^\s].*)$/) {
        $lang{$lang}{$key} .= ''.("\n"x$empty)."\n$1";
        $empty = 0;
        next;
      }
      # empty string (count them in case they're part of a multi-line locale string)
      if(/^\s*$/) {
        $empty++;
        next;
      }
      # something we didn't expect
      die "Don't know what to do with line $line\n";
    }
    close $F;

    # dev.
    use Data::Dumper 'Dumper';
    warn Dumper \%lang;
  }
}


{
  package VNDB::L10N::en;
  use base 'VNDB::L10N';
  our %Lexicon = (
    _AUTO => 1
  );
}

{
  package VNDB::L10N::ru;
  use base 'VNDB::L10N::en';
  our %Lexicon;
}


1;

