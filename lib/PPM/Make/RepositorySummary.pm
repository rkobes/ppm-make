package PPM::Make::RepositorySummary;

use strict;
use warnings;
use PPM::Make::Util qw(parse_ppd ppd2cpan_version);
use File::Copy;

our $VERSION = '0.97';

sub new {
  my $class = shift;
  my %args = @_;
  my $rep = $args{rep};
  die qq{Please supply the path to a repository of ppd files}
    unless $rep;
  die qq{The given repository directory "$rep" does not exist}
    unless -d $rep;
  opendir(my $dir, $rep) or die "Cannot opendir $rep: $!";
  my @ppds = sort {lc $a cmp lc $b} grep {$_ =~ /\.ppd$/} readdir $dir;
  closedir($dir);
  die qq{The repository directory "$rep" contains no ppd files}
    unless (scalar @ppds > 0);

  my $no_ppm4 = $args{no_ppm4};
  my $fhs = {
	     summary => {file => 'summary.ppm',
			fh => undef,
			start => \&summary_start,
			softpkg => \&summary_softpkg,
			end => \&summary_end,
			},
	     searchsummary => {file => 'searchsummary.ppm',
			       fh => undef,
			       start => \&searchsummary_start,
			       softpkg => \&searchsummary_softpkg,
			       end => \&searchsummary_end,
			},
	     package_lst => {file => 'package.lst',
			     fh => undef,
			     start => \&package_lst_start,
			     softpkg => \&package_lst_softpkg,
			     end => \&package_lst_end,
			    },
	    };
  unless ($no_ppm4) {
    $fhs->{package_xml} = {file => 'package.xml',
			   fh => undef,
			   start => \&package_xml_start,
			   softpkg => \&package_xml_softpkg,
			   end => \&package_xml_end,
			  };
  };
  my $self = {rep => $rep,
              ppds => \@ppds,
	      no_ppm4 => $no_ppm4,
	      arch => $args{arch},
	      fhs => $fhs,
             };
  bless $self, $class;
}

sub summary {
  my $self = shift;
  my $rep = $self->{rep};
  my $fhs = $self->{fhs};
  chdir($rep) or die qq{Cannot chdir to $rep: $!};

  foreach my $key (keys %$fhs) {
    my $tmp = $fhs->{$key}->{file} . '.TMP';
    open(my $fh, '>', $tmp) or die qq{Cannot open $tmp: $!};
    $fhs->{$key}->{fh} = $fh;
  }

  my $arch = $self->{arch};
  foreach my $key (keys %$fhs) {
    my @args = ($fhs->{$key}->{fh});
    push @args, $arch if ($arch and $key eq 'package_xml');
    $fhs->{$key}->{start}->(@args);
  }

  my $ppds = $self->{ppds};
  foreach my $ppd(@$ppds) {
    my $data;
    eval {$data = parse_ppd($ppd);};
    if ($@) {
      warn qq{Error in parsing $ppd: $@};
      next;
    }
    unless ($data and (ref($data) eq 'HASH')) {
      warn qq{No valid ppd data available in $ppd};
      next;
    }
    foreach my $key (keys %$fhs) {
      $fhs->{$key}->{softpkg}->($fhs->{$key}->{fh}, $data);
    }
  }

  foreach my $key (keys %$fhs) {
   $fhs->{$key}->{end}->($fhs->{$key}->{fh});
  }

  foreach my $key (keys %$fhs) {
    close($fhs->{$key}->{fh});
    my $real = $fhs->{$key}->{file};
    my $tmp =  $real . '.TMP';
    move($tmp, $real) or warn qq{Cannot rename $tmp to $real: $!};
  }
  return 1;
}

sub summary_start {
  my $fh = shift;
  print $fh <<"END";
<?xml version="1.0" encoding="UTF-8"?>
<REPOSITORYSUMMARY>
END
  return 1;
}

sub searchsummary_start {
  my $fh = shift;
  print $fh <<"END";
<?xml version="1.0" encoding="UTF-8"?>
<REPOSITORYSUMMARY>
END
  return 1;
}

sub package_lst_start {
  my $fh = shift;
  print $fh <<"END";
<?xml version="1.0" encoding="UTF-8"?>
<REPOSITORYSUMMARY>
END
  return 1;
}

sub package_xml_start {
  my $fh = shift;
  my $arch = shift;
  my $rs = $arch ? qq{<REPOSITORYSUMMARY ARCHITECTURE="$arch">} :
    q{<REPOSITORYSUMMARY>};
  print $fh <<"END";
<?xml version="1.0" encoding="UTF-8"?>
$rs
END
  return 1;
}

sub summary_end {
  my $fh = shift;
  print $fh <<"END";
</REPOSITORYSUMMARY>
END
  return 1;
}

sub searchsummary_end {
  my $fh = shift;
  print $fh <<"END";
</REPOSITORYSUMMARY>
END
  return 1;
}

sub package_lst_end {
  my $fh = shift;
  print $fh <<"END";
</REPOSITORYSUMMARY>
END
  return 1;
}

sub package_xml_end {
  my $fh = shift;
  print $fh <<"END";
</REPOSITORYSUMMARY>
END
  return 1;
}

sub summary_softpkg {
  my ($fh, $d) = @_;
  print $fh <<"END";
  <SOFTPKG NAME="$d->{SOFTPKG}->{NAME}" VERSION="$d->{SOFTPKG}->{VERSION}">
    <TITLE>$d->{TITLE}</TITLE>
    <ABSTRACT>$d->{ABSTRACT}</ABSTRACT>
    <AUTHOR>$d->{AUTHOR}</AUTHOR>
  </SOFTPKG>
END
  return 1;
}

sub searchsummary_softpkg {
  my ($fh, $d) = @_;
  print $fh <<"END";
  <SOFTPKG NAME="$d->{SOFTPKG}->{NAME}" VERSION="$d->{SOFTPKG}->{VERSION}">
    <TITLE>$d->{TITLE}</TITLE>
    <ABSTRACT>$d->{ABSTRACT}</ABSTRACT>
    <AUTHOR>$d->{AUTHOR}</AUTHOR>
END
  my $imp = $d->{IMPLEMENTATION};
  foreach my $item(@$imp) {
    print $fh <<"END";
    <IMPLEMENTATION>
      <ARCHITECTURE NAME="$item->{ARCHITECTURE}->{NAME}" />
    </IMPLEMENTATION>
END
  }
  print $fh <<"END";
  </SOFTPKG>
END
  return 1;
}

sub package_lst_softpkg {
  my ($fh, $d) = @_;

  print $fh <<"END";
  <SOFTPKG NAME="$d->{SOFTPKG}->{NAME}" VERSION="$d->{SOFTPKG}->{VERSION}">
    <TITLE>$d->{TITLE}</TITLE>
    <ABSTRACT>$d->{ABSTRACT}</ABSTRACT>
    <AUTHOR>$d->{AUTHOR}</AUTHOR>
END

  my $imp = $d->{IMPLEMENTATION};
  foreach my $item(@$imp) {
    print $fh <<"END";
    <IMPLEMENTATION>
END
    my $deps = $item->{DEPENDENCY};
    if (defined $deps and (ref($deps) eq 'ARRAY')) {
      foreach my $dep (@$deps) {
	print $fh <<"END";
      <DEPENDENCY NAME="$dep->{NAME}" VERSION="$dep->{VERSION}" />
END
      }
    }

    foreach (qw(OS ARCHITECTURE)) {
      next unless $item->{$_}->{NAME};
      print $fh qq{      <$_ NAME="$item->{$_}->{NAME}" />\n};
    }

    if (my $script = $item->{INSTALL}->{SCRIPT}) {
      my $install = 'INSTALL';
      if (my $exec = $item->{INSTALL}->{EXEC}) {
	$install .= qq{ EXEC="$exec"};
      }
      if (my $href = $item->{INSTALL}->{HREF}) {
	$install .= qq{ HREF="$href"};
      }
      print $fh qq{      <$install>$script</INSTALL>\n};
    }
    
    print $fh <<"END";
      <CODEBASE HREF="$item->{CODEBASE}->{HREF}" />
    </IMPLEMENTATION>
END
  }
  print $fh <<"END";
  </SOFTPKG>
END

  return 1;
}

sub package_xml_softpkg {
  my ($fh, $d) = @_;
  my $s_version = ppd2cpan_version($d->{SOFTPKG}->{VERSION});
  print $fh <<"END";
  <SOFTPKG NAME="$d->{SOFTPKG}->{NAME}" VERSION="$s_version">
    <ABSTRACT>$d->{ABSTRACT}</ABSTRACT>
    <AUTHOR>$d->{AUTHOR}</AUTHOR>
END
  my $imp = $d->{IMPLEMENTATION};
  my $size = scalar @$imp;
  my $sp = ($size == 1) ? '    ' : '      ';
  foreach my $item (@$imp) {
    print $fh <<"END";
    <IMPLEMENTATION>
END

    if (my $arch = $item->{ARCHITECTURE}->{NAME}) {
      print $fh qq{      <ARCHITECTURE NAME="$arch" />\n};
    }

    if (my $script = $item->{INSTALL}->{SCRIPT}) {
      my $install = 'INSTALL';
      if (my $exec = $item->{INSTALL}->{EXEC}) {
	$install .= qq{ EXEC="$exec"};
      }
      if (my $href = $item->{INSTALL}->{HREF}) {
	$install .= qq{ HREF="$href"};
      }
      print $fh qq{      <$install>$script</INSTALL>\n};
    }

    print $fh <<"END";
      <CODEBASE HREF="$item->{CODEBASE}->{HREF}" />
END
    if ($size == 1) {
      print $fh <<"END";
    </IMPLEMENTATION>
END
    }
    my $provide = $item->{PROVIDE};
    if ($provide and (ref($provide) eq 'ARRAY')) {
      foreach my $mod(@$provide) {
	my $string = qq{$sp<PROVIDE NAME="$mod->{NAME}"};
	if ($mod->{VERSION}) {
	  $string .= qq{ VERSION="$mod->{VERSION}"};
	}
	$string .= qq{ />\n};
	print $fh $string;
      }
    }

    my $deps = $item->{DEPENDENCY};
    if ($deps and (ref($deps) eq 'ARRAY')) {
      foreach my $dep (@$deps) {
#  ppm4 819 doesn't seem to like version numbers
#      my $p_version = ppd2cpan_version($dep->{VERSION});
#      print $fh 
#      qq{    <REQUIRE NAME="$dep->{NAME}" VERSION="$p_version" />\n};
	print $fh qq{$sp<REQUIRE NAME="$dep->{NAME}" />\n};
      }
    }
    if ($size > 1) {
      print $fh <<"END";
    </IMPLEMENTATION>
END
    }
  }

  print $fh qq{  </SOFTPKG>\n};
  return 1;
}

1;

__END__


=head1 NAME

PPM::Make::RepositorySummary - generate summary files for a ppm repository

=head1 SYNOPSIS

   use PPM::Make::RepositorySummary;
   my $rep = '/path/to/ppms';
   my $obj = PPM::Make::RepositorySummary->new(rep => $rep);
   $obj->summary();

=head1 DESCRIPTION

This module may be used to generate various summary files as used by
ActiveState's ppm system. It searches a given directory for I<ppd>
files, which are of the form

  <?xml version="1.0" encoding="UTF-8"?>
  <SOFTPKG NAME="Archive-Tar" VERSION="1,29,0,0">
    <TITLE>Archive-Tar</TITLE>
    <ABSTRACT>Manipulates TAR archives</ABSTRACT>
    <AUTHOR>Jos Boumans &lt;kane[at]cpan.org&gt;</AUTHOR>
    <IMPLEMENTATION>
      <DEPENDENCY NAME="IO-Zlib" VERSION="1,01,0,0" />
      <OS NAME="MSWin32" />
      <ARCHITECTURE NAME="MSWin32-x86-multi-thread-5.8" />
      <CODEBASE HREF="Archive-Tar.tar.gz" />
    </IMPLEMENTATION>
  </SOFTPKG>

and generates four types of files summarizing the information
found in all I<ppd> files found:

=over

=item summary.ppm

  <?xml version="1.0" encoding="UTF-8"?>
  <REPOSITORYSUMMARY>
    <SOFTPKG NAME="Archive-Tar" VERSION="1,29,0,0">
      <TITLE>Archive-Tar</TITLE>
      <ABSTRACT>Manipulates TAR archives</ABSTRACT>
      <AUTHOR>Jos Boumans &lt;kane[at]cpan.org&gt;</AUTHOR>
    </SOFTPKG>
    ...
  </REPOSITORYSUMMARY>

=item searchsummary.ppm

  <?xml version="1.0" encoding="UTF-8"?>
  <REPOSITORYSUMMARY>
    <SOFTPKG NAME="Archive-Tar" VERSION="1,29,0,0">
      <TITLE>Archive-Tar</TITLE>
      <ABSTRACT>Manipulates TAR archives</ABSTRACT>
      <AUTHOR>Jos Boumans &lt;kane[at]cpan.org&gt;</AUTHOR>
      <IMPLEMENTATION>
        <ARCHITECTURE NAME="MSWin32-x86-multi-thread-5.8" />
      </IMPLEMENTATION>
    </SOFTPKG>
    ...
  </REPOSITORYSUMMARY>

=item package.lst

  <?xml version="1.0" encoding="UTF-8"?>
  <REPOSITORYSUMMARY>
    <SOFTPKG NAME="Archive-Tar" VERSION="1,29,0,0">
      <TITLE>Archive-Tar</TITLE>
      <ABSTRACT>Manipulates TAR archives</ABSTRACT>
      <AUTHOR>Jos Boumans &lt;kane[at]cpan.org&gt;</AUTHOR>
      <IMPLEMENTATION>
        <DEPENDENCY NAME="IO-Zlib" VERSION="1,01,0,0" />
        <OS NAME="MSWin32" />
        <ARCHITECTURE NAME="MSWin32-x86-multi-thread-5.8" />
        <CODEBASE HREF="Archive-Tar.tar.gz" />
      </IMPLEMENTATION>
    </SOFTPKG>
    ...
  </REPOSITORYSUMMARY>

=item package.xml

  <?xml version="1.0" encoding="UTF-8"?>
  <REPOSITORYSUMMARY ARCHITECTURE="MSWin32-x86-multi-thread-5.8">
    <SOFTPKG NAME="Archive-Tar" VERSION="1.29">
      <ABSTRACT>Manipulates TAR archives</ABSTRACT>
      <AUTHOR>Jos Boumans &lt;kane[at]cpan.org&gt;</AUTHOR>
      <IMPLEMENTATION>
        <ARCHITECTURE NAME="MSWin32-x86-multi-thread-5.8" />
        <CODEBASE HREF="Archive-Tar.tar.gz" />
      </IMPLEMENTATION>
      <REQUIRE NAME="IO-Zlib" VERSION="1.01" />
      <PROVIDE NAME="Archive::Tar" VERSION="1.29" />
      <PROVIDE NAME="Archive::Tar::File" VERSION="1.21" />
    </SOFTPKG>
    ...
  </REPOSITORYSUMMARY>

=back

If multiple E<lt>IMPLEMETATIONE<gt> sections are present
in the ppd file, all will be included in the corresponding
summary files.

Options accepted by the I<new> constructor include

=over

=item rep =E<gt> '/path/to/ppds'

This option, which is required, specifies the path to where
the I<ppd> files are found. The summary files will be written
in this directory.

=item no_ppm4 =E<gt> 1

If this option is specified, the F<package.xml> file (which
contains some extensions used by ppm4) will not be generated.

=item arch =E<gt> 'MSWin32-x86-multi-thread-5.8'

If this option is given, it will be used as the
I<ARCHITECTURE> attribute of the I<REPOSITORYSUMMARY>
element of F<package.xml>.

=back

=head1 COPYRIGHT

This program is copyright, 2006, by Randy Kobes E<lt>r.kobes.uwinnipeg.caE<gt>.
It is distributed under the same terms as Perl itself.

=head1 SEE ALSO

L<PPM> and L<PPM::Make>

=cut

