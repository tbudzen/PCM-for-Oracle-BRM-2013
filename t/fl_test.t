use ExtUtils::testlib;
use Data::Dumper;
use Test::More tests => 1;
use Pcm;

ok
(
	$out = 
		Pcm::__parse_fl_from_str
		(
			"0 PIN_FLD_POID           POID [0] 0.0.0.1 /search -1 0\n" .
			"0 PIN_FLD_FLAGS           INT [0] 256\n" .
			"0 PIN_FLD_TEMPLATE        STR [0] \"select X from /config/notify where F1 = V1 \"\n" .
			"0 PIN_FLD_ARGS          ARRAY [1] allocated 20, used 1\n" .
			"1   PIN_FLD_EVENTS      ARRAY [0] allocated 20, used 1\n" .
			"2      PIN_FLD_TYPE_STR   STR [0] \"/event/session\"\n" .	
			"1   PIN_FLD_POID        POID [0] NULL\n" .
			"0 PIN_FLD_RESULTS       ARRAY [*] NULL array ptr"
		)
);
	
print Dumper($out);
