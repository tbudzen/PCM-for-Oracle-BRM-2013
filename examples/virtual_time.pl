use ExtUtils::testlib;
use Data::Dumper;
use Pcm;

$in =
    {
        "PIN_FLD_POID" => 
            {
                "db" => "0.0.0.1",
                "type" => "/",
                "id" => -1,
                "rev" => 0
            }
    };

($out, $ebuf) = Pcm::op("PCM_OP_GET_PIN_VIRTUAL_TIME", $in, 0);

print Dumper($out);
print Dumper($ebuf);