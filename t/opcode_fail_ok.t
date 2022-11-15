use ExtUtils::testlib;
use Data::Dumper;
use Test::More tests => 1;
use Pcm;

$in =
    {
        "PIN_FLD_POID" => 
            {
                "db" => "0.0.0.1111",
                "type" => "/aaaaaaaaaaaaaaaaaaaaaa",
                "id" => -1,
                "rev" => 0
            }
    };

ok(($out, $ebuf) = Pcm::op("PCM_OP_SEARCH", $in, 0));

print Dumper($out);
print Dumper($ebuf);