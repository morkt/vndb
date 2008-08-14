#!/usr/bin/perl

# create static/sf and static/st with subdirectories
chdir '/www/vndb/static';

sub mk {
  for (@_) {
    mkdir $_ or die "mkdir: $_: $!";
    chmod 0777, $_ or die "chmod: $_: $!";
  }
}

mk 'sf', 'st';
mk sprintf('sf/%02d',$_), sprintf('st/%02d',$_) for (0..99);

