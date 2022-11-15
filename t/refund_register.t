use ExtUtils::testlib;
use Data::Dumper;
use Pcm;
use Test::More tests => 1;

$a =
    {
        "PIN_FLD_POID"           => { "db" => "0.0.0.2", "type" => "/dummy", "id" => 0, "rev" => 52345320 },
        "TP_FLD_PAYMENT_NO"      => "PM/20000000000025",
        "PIN_FLD_ACCOUNT_NO"	 => "0.0.0.2-104244",
        "PIN_FLD_MODE"           => 1,
        "PIN_FLD_AMOUNT"         => 1.75,
        "TP_FLD_AMOUNT_INTEREST" => 2.25,
        "PIN_FLD_OPERATOR_STR"   => "Piotr Kowalczyk",
        "PIN_FLD_REFUND"  		 =>
        {
        	"PIN_FLD_ADDRESS" 		=> "Adres testowy",
        	"TP_FLD_CONTR_NAME" 	=> "Test 1",
        	"TP_FLD_CONTR_ADDR" 	=> "Adres 1",
        	"TP_FLD_REFUND_METHOD"  => "1",
        	"PIN_FLD_BANK_ACCOUNT"  => "0.0.0.2-104244"
        }
    };
        
ok(($out, $ebuf) = Pcm::op("TP_OP_PYMT_REFUND_REGISTER", $a, 0));

print Dumper($a);
print Dumper($out);
print Dumper($ebuf);