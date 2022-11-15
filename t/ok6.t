# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Pcm.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use ExtUtils::testlib;
use Data::Dumper;
use Test::More tests => 2;

BEGIN { use_ok('Pcm') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

$in = {
        "PIN_FLD_POID" => 
            {
                "db" => "0.0.0.2",
                "type" => "/bill",
                "id" => -1,
                "rev" => 0
            },
        "PIN_FLD_INCLUDE_CHILDREN" => 1
      };

ok(($out, $ebuf) = Pcm::op("PCM_OP_AR_GET_BILLS", $in, 0));

print Dumper($in);
print Dumper($out);
print Dumper($ebuf);