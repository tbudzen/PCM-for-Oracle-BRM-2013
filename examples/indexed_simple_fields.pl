use ExtUtils::testlib;
use Data::Dumper;
use Pcm;

$in =
{
      "PIN_FLD_POID" => { "db" => "0.0.0.1", "type" => "/search", "id" => -1, "rev" => 0 },
      "PIN_FLD_TEMPLATE" => "select count(1), sum(F2) from /event where F1 = V1 ",
      "PIN_FLD_FLAGS" => 16,
      "PIN_FLD_ARGS" =>
	  {
                  1 => { "PIN_FLD_ACCOUNT_OBJ" => { "db" => "0.0.0.1", "type" => "/account", "id" => 1, "rev" => 0 } },
                  2 => { "PIN_FLD_NET_QUANTITY" => 0.20 }
	  },
      "PIN_FLD_RESULTS" => 
      {
                1 =>
                { 
                  "PIN_FLD_AMOUNT" => # Indexed PIN_FLDT_DECIMAL field
                  {
                  		1 => 0.05345, 
                  		2 => 0.03425
                  }
               }
      }
};

($out, $ebuf) = Pcm::op("PCM_OP_SEARCH", $in, 0);

print Dumper($out);
