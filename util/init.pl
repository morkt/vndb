#!/usr/bin/perl


# This script should be run after you've somehow managed to fetch
# all the versioned files from the git repo.


print "Initializing the files and directories needed to run VNDB...\n";


# determine our root directory 
use Cwd 'abs_path';
our $ROOT;
BEGIN {
  ($ROOT = abs_path $0) =~ s{/util/init\.pl$}{};
}


print "  Using project root: $ROOT\n";
print "\n";



print "Creating directory structures...\n";
for my $d (qw| cv rg st sf |) {
  print "  /static/$d\n";
  mkdir "$ROOT/static/$d" or die "mkdir '$ROOT/static/$d': $!\n";
  for my $i (0..99) {
    my $n = sprintf '%s/static/%s/%02d', $ROOT, $d, $i;
    mkdir $n or die "mkdir '$n': $!\n";
    chmod 0777, $n or die "chmod 777 '$n': $!\n";
  }
}
print "\n";


print "Creating /www\n";
print "  You can use this directory to store all files you want to\n";
print "  be available from the main domain. A favicon.ico for example.\n";
mkdir "$ROOT/www" or die $!;
print "\n";


print "Writing robots.txt in /static and /www\n";
print "  You probably don't want your personal copy of VNDB to end up\n";
print "  in the google results, so I'll install a default robots.txt\n";
print "  for you. You're free to modify them as you wish.\n";
for ('static/robots.txt', 'www/robots.txt') {
  print "  $_ exists, skipping...\n", next if -f "$ROOT/$_";
  open my $F, '>', "$ROOT/$_" or die "$_: $!\n";
  print $F "User-agent: *\nDisallow: /\n";
  close $F;
}
print "\n";


if(!-f "$ROOT/data/config.pl") {
  # TODO: create a template config file
  print "No custom config file found, please write one!\n";
}
print "\n";


print "Everything is initialized! Now make sure to configure your\n";
print "webserver and to initialize a postgresql database (using\n";
print "dump.sql)\n";




