use ExtUtils::testlib;
use Data::Dumper;
use Pcm;

$opcode = "PCM_OP_SEARCH";
$flags = 0;
$in =
    {
        "PIN_FLD_POID" => 
            {
                "db" => "0.0.0.1",
                "type" => "/search",
                "id" => -1,
                "rev" => 0
            },
        "PIN_FLD_FLAGS" => 0,
        "PIN_FLD_TEMPLATE" => "select X from /account where F1 like V1 ",
        "PIN_FLD_ARGS" =>
            {
                1 =>
                {
                    "PIN_FLD_POID" =>
                        {
                            "db" => "0.0.0.1",
                            "type" => "/account",
                            "id" => -1,
                            "rev" => 0
                        }
                }
            },
        "PIN_FLD_RESULTS" => 
            {
            	"10" => undef
            }
    };

($out, $ebuf) = Pcm::op($opcode, $in, $flags);

print Dumper($out);
