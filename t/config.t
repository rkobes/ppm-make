#!perl
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';
use Test;
use strict;
use Cwd;
my $cwd = getcwd;
BEGIN { plan tests => 22 };
use PPM::Make;
use Config;
use File::Path;
use File::Find;
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.


$ENV{PPM_CFG} = "$cwd/t/ppm.cfg";
my $ppm = PPM::Make->new(arch => 'foo');
ok($ppm);
ok(ref($ppm), 'PPM::Make');
my $opts = $ppm->{opts};
ok($opts);
ok( $opts->{upload}->{user}, 'sarah');
ok( $opts->{upload}->{passwd}, 'justina');
ok( $opts->{upload}->{ppd}, '/home/to/wherever');
ok( $opts->{upload}->{host}, 'a.galaxy.far.far.away');
ok( $opts->{upload}->{ar}, undef);
ok( $opts->{binary}, 'http://www.foo.com/bar');
ok( $opts->{vs}, 1);
$ppm = PPM::Make->new(arch => 'bar');
$opts = $ppm->{opts};
ok( $opts->{binary}, 'http://www.foo.com/bar');
ok( $opts->{vs}, undef);
ok( $opts->{upload}->{ppd}, '/path/to/ppds');
ok( $opts->{upload}->{ar}, 'x86');
$ppm = PPM::Make->new(arch => 'harry');
$opts = $ppm->{opts};
ok( $opts->{binary}, 'http://www.foo.com/bar');
ok( $opts->{vs}, 1);
ok( $opts->{upload}->{host}, undef);
$ppm = PPM::Make->new(arch => 'foo', vs => 0, binary => 'http://localhost',
		     upload => {ppd => '/another/path', user => 'lianne'});
$opts = $ppm->{opts};
ok( $opts->{binary}, 'http://localhost');
ok( $opts->{vs}, 0);
ok( $opts->{upload}->{ppd}, '/another/path');
ok( $opts->{upload}->{user}, 'lianne');

