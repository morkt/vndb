#!/usr/bin/perl


package VNDB;

use strict;
use warnings;


use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/vndb\.pl$}{}; }


use lib $ROOT.'/yawf/lib';
use lib $ROOT.'/lib';


use YAWF;


our(%O, %S);


# load settings from global.pl
require $ROOT.'/data/global.pl';


YAWF::init(
  %O,
  namespace => 'VNDB',
  object_data => \%S
);


