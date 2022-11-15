use ExtUtils::MakeMaker;
use Config;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Pcm',
    VERSION_FROM      => 'lib/Pcm.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Pcm.pm', # retrieve abstract from module
       AUTHOR         => '') : ()),
    LIBS              => [ "-L$ENV{PIN_HOME}/lib",
            . ($Config{archname} =~ /i686-linux/ ? '-melf_i386' : '')
            . ($Config{archname} =~ /x86_64/
                    ?  ' -lportal64 -lpcmext64'
                    :  ' -lportal -lpcmext')],

    ( $Config{archname} =~ /i686-linux/ ?
        (LDDLFLAGS    => '-m elf_i386 -shared -fPIC') : ()),
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => "-I. -I$ENV{PIN_HOME}/include",
    CCFLAGS           => ($Config{archname} =~ /x86_64/ ? '-m64' : '-m32'),
    # Un-comment this if you add C files to link with later:
    #OBJECT            => '$(O_FILES) ', # link all the C files too
);
