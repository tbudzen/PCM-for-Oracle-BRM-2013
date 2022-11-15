use ExtUtils::testlib;
use Data::Dumper;
use Pcm;

$in =
    {
        "PIN_FLD_POID" => { "db" => "0.0.0.1", "type" => "/account", "id" => 1, "rev" => 0 },
        "PIN_FLD_ACCOUNT_OBJ" => { "db" => "0.0.0.1", "type" => "/account", "id" => 1, "rev" => 0 },
        "PIN_FLD_PROGRAM_NAME" => "Test",
        "PIN_FLD_BILLINFO_OBJ" => { "db" => "0.0.0.1", "type" => "/billinfo", "id" => 1, "rev" => 0 },
        "PIN_FLD_CURRENCY" => 840,
        "PIN_FLD_AMOUNT" => 125.00,
        "PIN_FLD_PAYMENT" =>
        {
    		"PIN_FLD_AMOUNT" => 125.00,
    		"PIN_FLD_COMMAND" => 0,
    		"PIN_FLD_PAY_TYPE" => 10001,
    		"PIN_FLD_CURRENCY" => 840,
    		"PIN_FLD_TRANS_ID" => "Test-1111111"
        }
    };

($out, $ebuf) = Pcm::op("PCM_OP_BILL_RCV_PAYMENT", $in, 0);

print Dumper($out);
