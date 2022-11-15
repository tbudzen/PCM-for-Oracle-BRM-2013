use ExtUtils::testlib;
use Data::Dumper;
use Pcm;

$in =
    {
        "PIN_FLD_POID" => 
            {
                "db" => "0.0.0.1",
                "type" => "/dd/objects",
                "id" => -1,
                "rev" => 0
            },
        "PIN_FLD_OBJ_DESC" =>
        	{
        		0 =>
        		{
        			"PIN_FLD_NAME" => "/account"
        		}
        	}
    };

$opcode = "PCM_OP_SDK_GET_OBJ_SPECS";

($out, $ebuf) = Pcm::op($opcode, $in, 0);

print Dumper($opcode);
print Dumper($in);
print Dumper($out);