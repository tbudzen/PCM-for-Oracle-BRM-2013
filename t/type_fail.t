use ExtUtils::testlib;
use Data::Dumper;
use Test::More tests => 1;
use Pcm;

$in =
    {
        "PIN_FLD_POID" => 
            {
                "db" => "0.0.0.2",
                "type" => "/",
                "id" => -1,
                "rev" => 0
            },
		"PIN_FLD_ACCOUNT_NO" => "",
		"PIN_FLD_ACCOUNT_OBJ" => 
            {
                "db" => "0.0.0.2",
                "type" => "/",
                "id" => -1,
                "rev" => 0
            },
        "TP_FLD_REQUEST_NO" => "",
        "PIN_FLD_TYPE" => 2,
        "PIN_FLD_AMOUNT" => "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "PIN_FLD_PROGRAM_NAME" => "test",
        "PIN_FLD_OPERATOR_STR" => "Jan Kowalski",
        "TP_FLD_PAYMENT_NO" => "",
        "TP_FLD_PAYMENT_INFO" =>
        {
       		"PIN_FLD_ORDER_DATE" => 1372335909,
       		"PIN_FLD_ENTERED_DATE" => 1372335909,
       		"TP_FLD_TITLE_STR1" => "Tytu³ przelewu 1",
       		"TP_FLD_TITLE_STR2" => "Tytu³ przelewu 2",
       		"TP_FLD_BANK_FILENAME" => "bank_filename",
       		"PIN_FLD_CHANNEL_ID" => 0,
       		"PIN_FLD_ORDER_OBJ" =>
            {
                "db" => "0.0.0.2",
                "type" => "/",
                "id" => -1,
                "rev" => 0
            },
        	"TP_FLD_SERAT_ID_STR" => "",
        	"TP_FLD_SOURCE_OBJ" =>
            {
                "db" => "0.0.0.2",
                "type" => "/",
                "id" => -1,
                "rev" => 0
            },
        	"TP_FLD_REVERSAL_OBJ" =>
            {
                "db" => "0.0.0.2",
                "type" => "/",
                "id" => -1,
                "rev" => 0
            },
        	"TP_FLD_BILL_NO" => "",
#        	"PIN_FLD_NKP_ID" => 0,
        	"TP_FLD_HASH_ID" => ""	
        }	
    };

print Dumper($in);

ok(($out, $ebuf) = Pcm::op("TP_OP_PYMT_COLLECT", $in, 0));

print Dumper($out);
print Dumper($ebuf);

