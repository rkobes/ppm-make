#!perl
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';
use Test;
use strict;
use Cwd;
my $cwd = getcwd;
BEGIN { plan tests => 44 };
use PPM::Make;
use Config;
use File::Path;
use File::Find;
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.

my $ppm = PPM::Make->new(upload => {ppd => "$cwd/t"}, no_cfg => 1);
ok($ppm);
my $name = 'PPM-Make';
my $ppd = $name . '.ppd';
my $tgz = $name . '.tar.gz';
$ppm->make_ppm();

for ($ppd, $tgz, "t/$ppd", "t/$tgz") {
  if (-e $_) {
    ok(1);
  }
  else {
    ok(qq{'$_' not created}, 1);
  }
}

my $author = q{Randy Kobes &lt;r.kobes@uwinnipeg.ca&gt;};
my $abstract = q{Make a ppm package from a CPAN distribution};
my $d = PPM::Make::parse_ppd($ppd);
ok($d);
ok($d->{SOFTPKG}->{NAME}, $name);
ok($d->{TITLE}, $name);
ok($d->{ABSTRACT}, $abstract);
ok($d->{AUTHOR}, $author);
ok($d->{OS}->{NAME}, $Config{osname});
my $arch = $Config{archname};
if ($] >= 5.008) {
   my $vstring = sprintf "%vd", $^V;
   $vstring =~ s/\.\d+$//;
   $arch .= "-$vstring";
}
ok($d->{ARCHITECTURE}->{NAME}, $arch);
ok($d->{CODEBASE}->{HREF}, $tgz); 

my $provides = $d->{PROVIDE};
ok($provides);
ok(ref($provides) eq 'ARRAY');
my $has;
foreach my $entry (@$provides) {
  $has->{$entry->{NAME}} = $entry->{VERSION};
}
my @mods = qw(PPM::Make PPM::Make::Util PPM::Make::Install
                  PPM::Make::RepositorySummary PPM::Make::Config
                  PPM::Make::Meta PPM::Make::Bundle);
foreach my $mod(@mods) {
  ok(defined $has->{$mod});
  ok($has->{$mod} > 0);
}

my $is_Win32 = ($d->{OS}->{NAME} =~ /Win32/i); 

my @f;
if ($is_Win32) {
    finddepth(sub { push @f, $File::Find::name
                        unless $File::Find::name =~ m!blib/man\d!;
                    print $File::Find::name,"\n"}, 'blib');
}
else {
    finddepth(sub {push @f, $File::Find::name; 
                   print $File::Find::name,"\n"}, 'blib');
}

my $tar = $ppm->{has}->{tar};
my $gzip = $ppm->{has}->{gzip};
my @files;
if ($tar eq 'Archive::Tar' and $gzip eq 'Compress::Zlib') {
   require Archive::Tar;
   require Compress::Zlib;
   my $tar = Archive::Tar->new($tgz, 1);
   @files = $tar->list_files();
}

else {
   open(TGZ, "$gzip -dc $tgz \| $tar tvf - |");
   while (<TGZ>) {
      chomp;
      s!.* (blib\S*)!$1!;
      push @files, $_;
  }
  close(TGZ) or die "$!\n";;
}

ok($#f, $#files);
unlink ($ppd, $tgz, "t/$ppd", "t/$tgz");
$arch = 'c-wren';
my $url = 'http://www.disney.com/ppmpackages/';
my $script = 'README';
my $exec = 'notepad.exe';
my @args = ($ppm->{has}->{perl}, '-Mblib', 'bin/make_ppm',
        '-n', '-a', $arch, '-b', $url,
        '-s', $script, '-e', $exec, '--no_cfg');
system(@args) == 0 or die "system @args failed: $?";

for ($ppd, $tgz) {
  if (-e $_) {
    ok(1);
  }
  else {
    ok(qq{'$_' not created}, 1);
  }
}

$d = PPM::Make::parse_ppd($ppd);
ok($d);
ok($d->{SOFTPKG}->{NAME}, $name);
ok($d->{TITLE}, $name);
ok($d->{ABSTRACT}, $abstract);
ok($d->{AUTHOR}, $author);
ok($d->{OS}->{NAME}, $Config{osname});
ok($d->{ARCHITECTURE}->{NAME}, $arch);
ok($d->{CODEBASE}->{HREF}, $url . $arch . '/' . $tgz); 
ok($d->{INSTALL}->{SCRIPT}, $script);
ok($d->{INSTALL}->{EXEC}, $exec);

@f = ();
@files = ();
if ($is_Win32) {
    finddepth(sub { push @f, $File::Find::name
                        unless $File::Find::name =~ m!blib/man\d!;
                    print $File::Find::name,"\n"}, 'blib');
}
else {
    finddepth(sub {push @f, $File::Find::name; 
                   print $File::Find::name,"\n"}, 'blib');
}

if ($tar eq 'Archive::Tar' and $gzip eq 'Compress::Zlib') {
   require Archive::Tar;
   require Compress::Zlib;
   my $tar = Archive::Tar->new($tgz, 1);
   @files = $tar->list_files();
}

else {
   open(TGZ, "$gzip -dc $tgz \| $tar tvf - |");
   while (<TGZ>) {
      chomp;
      s!.* (blib\S*)!$1!;
      push @files, $_;
  }
  close(TGZ) or die "$!\n";;
}
ok($#f+1, $#files);
unlink ($ppd, $tgz);
