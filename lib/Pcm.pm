package Pcm;

use 5.008000;
use strict;
use warnings;
use vars;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Pcm ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '1.00-beta';

require XSLoader;
XSLoader::load('Pcm', $VERSION); # <-- We can use Pcm methods as the module is loaded (?)

# Preloaded methods go here.

sub collect_pcm_ops # --> PCM Perl bridge
{
}

sub create_global_constant 
{ 
	vars->import("\$$_[0]") 
}

BEGIN 
{ 
	create_global_constant "bah"; 
	$bah = "blah"; 
	hello();
	print $bah, "\n";
}

1;
__END__
