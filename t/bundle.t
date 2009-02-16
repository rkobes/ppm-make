#!perl
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';
use Test;
use strict;
use Cwd;
require File::Spec;
use File::Path;
my $cwd = getcwd;
BEGIN { plan tests => 42 };
use PPM::Make::Bundle;
use Config;
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.

my @ppds = qw(AppConfig.ppd File-HomeDir.ppd
	     Win32-TieRegistry.ppd Win32API-Registry.ppd);
my @tgz_base = qw(AppConfig-1.63 File-HomeDir-0.58
		 Win32-TieRegistry-0.25 Win32API-Registry-0.27);
my %exts = ('MSWin32-x86-multi-thread-5.8' => 'PPM58',
	    'MSWin32-x86-multi-thread' => 'PPM56');

my $rep = File::Spec->catdir($cwd, 't', 'ppms');
ok(-d $rep);
foreach my $arch (keys %exts) {
  my $bundle = PPM::Make::Bundle->new(no_cfg => 1, 
				      reps => [($rep)],
				      dist => 'AppConfig',
				      arch => $arch);
  ok($bundle);
  ok(ref($bundle), 'PPM::Make::Bundle');
  $bundle->make_bundle();
  my $build_dir = $bundle->{build_dir};
  ok(-d $build_dir);
  for my $ppd (@ppds) {
    my $remote = File::Spec->catfile($build_dir, "$ppd.orig");
    my $local = File::Spec->catfile($cwd, 't', 'ppms', $ppd);
    ok(-f $remote);
    ok(-s $remote, -s $local);
  }
  for my $tgz (@tgz_base) {
    my $ar = $tgz . '-' . $exts{$arch} . '.tar.gz';
    my $remote = File::Spec->catfile($build_dir, $ar);
    my $local = File::Spec->catfile($cwd, 't', 'ppms', $ar);
    ok(-f $remote);
    ok(-s $remote, -s $local);
  }
  my $zipdist = File::Spec->catfile($cwd, 'Bundle-AppConfig.zip');
  ok(-f $zipdist);
  unlink ($zipdist);
  rmtree($build_dir, 1, 1) if (defined $build_dir and -d $build_dir);
}
