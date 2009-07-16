#!/usr/bin/perl


#
#  Multi  -  core namespace for initialisation and global variables
#

package Multi;

use strict;
use warnings;
use Cwd 'abs_path';


our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/multi\.pl$}{}; *VNDB::ROOT = \$ROOT }
use lib $VNDB::ROOT.'/lib';

use Multi::Core;
require $VNDB::ROOT.'/data/global.pl';

Multi::Core->run();


