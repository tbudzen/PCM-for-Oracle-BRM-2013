use ExtUtils::testlib;
use Data::Dumper;
use Pcm;

$opcode = "PCM_OP_SEARCH";
$flags = 0;
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
                  "PIN_FLD_AMOUNT" =>
                  {
                  		1 => 0.05345, 
                  		2 => 0.03425
                  }
               }
      }
};

print Dumper($in);

($out, $ebuf) = Pcm::op($opcode, $in, $flags);

print Dumper($out);

open FILE, ">out.txt" or die $!;
print FILE Dumper($opcode);
print FILE Dumper($in);
print FILE Dumper($out);
close FILE;