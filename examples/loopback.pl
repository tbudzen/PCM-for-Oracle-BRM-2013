use ExtUtils::testlib;
use Data::Dumper;
use Pcm;

$opcode = "PCM_OP_TEST_LOOPBACK";
$flags = 0;
$in =
    {
        "PIN_FLD_POID" => # Normal POID
            {
                "db" => "0.0.0.1",
                "type" => "/search",
                "id" => -1,
                "rev" => 12345678
            },
        "PIN_FLD_SERVICE_OBJ" => undef, # NULL POID pointer
        "PIN_FLD_BAL_IMPACTS" => undef, # NULL array pointer
        "PIN_FLD_INHERITED_INFO" => undef, # NULL substruct pointer
        "PIN_FLD_FLAGS" => 512, # Integer
        "PIN_FLD_TEMPLATE" => "select X from /account where F1 like V1 ", # String
        "TP_FLD_PAYMENT_INFO" => # Array
       	{
       		1 => { "PIN_FLD_AMOUNT" => 15.00 },
       		2 => { "PIN_FLD_AMOUNT" => 25.00 },
       		3 => { "PIN_FLD_AMOUNT" => undef }, # NULL decimal pointer
       		5 => { "PIN_FLD_AMOUNT" => 55.00 },
       		6 => { "PIN_FLD_TEMPLATE" => undef }, # NULL string pointer
       		7 => { "PIN_FLD_AMOUNT" => 65.00 }      	
       	},
        "PIN_FLD_ARGS" => # Normal array
            {
                1 =>
                {
                    "PIN_FLD_POID" =>
                    {
                        "db" => "0.0.0.1",
                        "type" => "/account",
                        "id" => -1
                    }
                },
                1024 =>
                {
        			"PIN_FLD_POID" => 
            		{
                		"db" => "0.0.0.1",
                		"type" => "/account",
                		"id" => -1,
                		"rev" => 12345678
            		}
            	}
            },
        "PIN_FLD_RESULTS" => 
            {
                1 =>
                { 
                  "PIN_FLD_AMOUNT" => # Indexed simple field
                  {
                  		1 => 0.05345, 
                  		2 => 0.03425,
                  		27 => -0.5,
                  		345 => 0.00000000001
                  }
               }
            },   
        "TP_FLD_REFUND_INFO" => # Normal substruct
        {
        		"PIN_FLD_ADDRESS" 		=> "Adres testowy",
        		"TP_FLD_CONTR_NAME" 	=> "Test 1",
        		"TP_FLD_CONTR_ADDR" 	=> "Adres 1",
        		"TP_FLD_REFUND_METHOD"  => "1",
        		"PIN_FLD_BANK_ACCOUNT"  => "0.0.0.2-104244"
        },         
        "PIN_FLD_REFUND" => # Indexed substruct
        {
        	7 => 
        	{
        		"PIN_FLD_ADDRESS" 		=> "Adres testowy",
        		"TP_FLD_CONTR_NAME" 	=> "Test 1",
        		"TP_FLD_CONTR_ADDR" 	=> "Adres 1",
        		"TP_FLD_REFUND_METHOD"  => "1",
        		"PIN_FLD_BANK_ACCOUNT"  => "0.0.0.2-104244"
        	},
        	8 => 
        	{
        		"PIN_FLD_ADDRESS" 		=> "Adres testowy 2",
        		"TP_FLD_CONTR_NAME" 	=> "Test 2",
        		"TP_FLD_CONTR_ADDR" 	=> "Adres 2",
        		"TP_FLD_REFUND_METHOD"  => "1",
        		"PIN_FLD_BANK_ACCOUNT"  => "0.0.0.3-104277"
        	}
        }
    };

print Dumper($in);

($out,  $ebuf) = Pcm::op($opcode, $in,  $flags);
($out2, $ebuf) = Pcm::op($opcode, $out, $flags); # To check reference handling

print Dumper($out);
print Dumper($out2);
