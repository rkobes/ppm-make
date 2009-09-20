package PPM::Make::Search;
use strict;
use warnings;

use PPM::Make::Config qw(WIN32 HAS_CPAN HAS_PPM HAS_MB);
use PPM::Make::Util qw(:all);
use XML::Parser;
use LWP::Simple;

our $VERSION = '0.97';
our ($ERROR);

my $info_soap;
my $info_uri = 'http://theoryx5.uwinnipeg.ca/Apache/InfoServer';
my $info_proxy = 'http://theoryx5.uwinnipeg.ca/cgi-bin/ppminfo.cgi';
my $meta = 'http://cpan.uwinnipeg.ca/meta/';

sub new {
  my $class = shift;
  my $self = {query => undef,
	      args => {},
	      todo => [],
	      mod_results => {},
	      dist_results => {},
	      dist_id => {},
	     };
  my $soap;
  eval {require SOAP::Lite;};
  unless ($@) {
    eval {$soap = make_info_soap();};
  }
  unless ($@) {
    $self->{soap} = $soap;
  }
  my $meta = shift;
  $self->{meta} = $meta if defined $meta;
  bless $self, $class;
}

sub make_info_soap {

  return SOAP::Lite
    ->uri($info_uri)
      ->proxy($info_proxy,
	      options => {compress_threshold => 10000})
	->on_fault(sub { my($soap, $res) = @_; 
			 warn "SOAP Fault: ", 
                           (ref $res ? $res->faultstring 
                            : $soap->transport->status),
                              "\n";
                         return undef;
		       });
}

sub search {
  my ($self, $query, %args) = @_;
  unless ($query) {
    $ERROR = q{Please specify a query term};
    return;
  }
  $self->{query} = $query;
  $self->{args} = \%args;
  $self->{todo} = ref($query) eq 'ARRAY' ? $query : [$query];
  my $mode = $args{mode};
  unless ($mode) {
    $ERROR = q{Please specify a mode within the search() method};
    return;
  }
  unless ($mode eq 'mod' or $mode eq 'dist') {
    $ERROR = q{Only 'mod' or 'dist' modes are supported};
    return;
  }
  return ($mode eq 'mod') ?
    $self->mod_search(%args) : $self->dist_search(%args);
}

sub mod_search {
  my $self = shift;
  if (defined $self->{cpan_meta}) {
    return 1 if $self->meta_mod_search();
  }
  if (defined $self->{soap}) {
    return 1 if $self->soap_mod_search();
  }
  if (HAS_CPAN) {
    return 1 if $self->cpan_mod_search();
  }
  return 1 if $self->ppd_mod_search();
  $ERROR = q{Not all query terms returned a result};
  return 0;
}

sub meta_mod_search {
  my $self = shift;
  my @mods = @{$self->{todo}};
  my @todo = ();
  my $cpan_meta = $self->{cpan_meta};
  foreach my $m (@mods) {
    my $id = $cpan_meta->instance('CPAN::Module', $m);
    unless (defined $id) {
      push @todo, $m;
      next;
    }
    my $mods = {};
    my $string = $id->as_string;
    my $mod;
    if ($string =~ /id\s*=\s*(.*?)\n/m) {
      $mod = $1;
      next unless $mod;
    }
    $mods->{mod_name} = $mod;
    if (my $v = $id->cpan_version) {
      $mods->{mod_vers} = $v;
    }
    if ($string =~ /\s+DESCRIPTION\s+(.*?)\n/m) {
      $mods->{mod_abs} = $1;
    }
    if ($string =~ /\s+CPAN_USERID.*\s+\((.*)\)\n/m) {
      $mods->{author} = $1;
    }
    if ($string =~ /\s+CPAN_FILE\s+(\S+)\n/m) {
      $mods->{dist_file} = $1;
    }
    ($mods->{cpanid} = $mods->{dist_file}) =~ s{\w/\w\w/(\w+)/.*}{$1};
    $mods->{dist_name} = file_to_dist($mods->{dist_file});
    $self->{mod_results}->{$mod} = $mods;
    $self->{dist_id}->{$mods->{dist_name}} ||=
      check_id($mods->{dist_file});
  }
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub cpan_mod_search {
  my $self = shift;
  my @mods = @{$self->{todo}};
  my @todo = ();
  foreach my $m (@mods) {
    my $obj = CPAN::Shell->expand('Module', $m);
    unless (defined $obj) {
      push @todo, $m;
      next;
    }
    my $mods = {};
    my $string = $obj->as_string;
    my $mod;
    if ($string =~ /id\s*=\s*(.*?)\n/m) {
      $mod = $1;
      next unless $mod;
    }
    $mods->{mod_name} = $mod;
    if (my $v = $obj->cpan_version) {
      $mods->{mod_vers} = $v;
    }
    if ($string =~ /\s+DESCRIPTION\s+(.*?)\n/m) {
      $mods->{mod_abs} = $1;
    }
    if ($string =~ /\s+CPAN_USERID.*\s+\((.*)\)\n/m) {
      $mods->{author} = $1;
    }
    if ($string =~ /\s+CPAN_FILE\s+(\S+)\n/m) {
      $mods->{dist_file} = $1;
    }
    ($mods->{cpanid} = $mods->{dist_file}) =~ s{\w/\w\w/(\w+)/.*}{$1};
    $mods->{dist_name} = file_to_dist($mods->{dist_file});
    $self->{mod_results}->{$mod} = $mods;
    $self->{dist_id}->{$mods->{dist_name}} ||=
      check_id($mods->{dist_file});
  }
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub ppd_mod_search {
  my $self = shift;
  my @mods = @{$self->{todo}};
  my @todo = ();
  if (scalar @mods > 0) {
    foreach my $mod (@mods) {
      my $query = ($mod =~ /::/) ? $mod : ($mod . '::');
      my $content = get($meta . $query . '/META.ppd');
      unless (defined $content and $content =~ /xml version/) {
        push @todo, $mod;
        next;
      }
      my $d = parse_ppd($content);
      my $info = {};
      my $provide = $d->{PROVIDE};
      foreach my $item (@$provide) {
        if ($item->{NAME} eq $mod) {
	      $info->{mod_name} = $item->{NAME};
          $info->{mod_vers} = $item->{VERSION};
        }
      }
      next unless defined $info->{mod_name};
      (my $trial = $d->{TITLE}) =~ s/-/::/g;
      if ($trial eq $mod) {
        $info->{mod_abs} = $d->{ABSTRACT};
      }
      my $author = $d->{AUTHOR};
      $author =~ s/&lt;/</;
      $author =~ s/&gt;/>/;
      $info->{author} = $author;
      (my $cpanfile = $d->{CODEBASE}->{HREF}) =~ s{$meta/cpan/authors/id/}{};
      (my $cpanid = $cpanfile) =~ s{\w/\w\w/(\w+)/.*}{$1};
      $info->{cpanid} = $cpanid;
      $info->{dist_file} = $cpanfile;
      $info->{dist_name} = file_to_dist($cpanfile);
      $self->{mod_results}->{$mod} = $info;
      $self->{dist_id}->{$info->{dist_name}} ||=
        check_id($info->{dist_file});
    }
  }
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub soap_mod_search {
  my $self = shift;
  my $soap = $self->{soap};
  my $query = $self->{todo};
  my %mods = map {$_ => 1} @{$query};
  my $result = $soap->mod_info($query);
  eval {$result->fault};
  if ($@) {
      $ERROR = $@;
      return;
  }
  $result->fault and do {
      $ERROR = join ', ', 
          $result->faultcode, 
              $result->faultstring;
      return;
  };
  my $results = $result->result();
  return unless ($results);
  if (ref($query) eq 'ARRAY') {
    foreach my $entry (keys %$results) {
      delete $mods{$entry} if (defined $mods{$entry});
      my $info = $results->{$entry};
      my $email = $info->{email} || $info->{cpanid} . '@cpan.org';
      $info->{author} = $info->{fullname} . qq{ <$email> };
      (my $prefix = $info->{cpanid}) =~ s{^(\w)(\w)(\w+)}{$1/$1$2/$1$2$3};
      $info->{dist_file} = $prefix . '/' . $info->{dist_file};
      $self->{mod_results}->{$entry} = $info;
      $self->{dist_id}->{$info->{dist_name}} ||=
	check_id($info->{dist_file});
    }
  }
  else {
    my $email = $results->{email} || $results->{cpanid} . '@cpan.org';
    my $mod_name = $results->{mod_name};
    $results->{author} = $results->{fullname} . qq{ &lt;$email&gt;};
    (my $prefix = $results->{cpanid}) =~ s{^(\w)(\w)(\w+)}{$1/$1$2/$1$2$3};
    $results->{dist_file} = $prefix . '/' . $results->{dist_file};
    $self->{mod_results}->{$mod_name} = $results;
    delete $mods{$mod_name} if (defined $mods{$mod_name});
    $self->{dist_id}->{$results->{dist_name}} ||=
      check_id($results->{dist_file});
  }

  my @todo = keys %mods;
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub dist_search {
  my $self = shift;
  if (defined $self->{cpan_meta}) {
    return 1 if $self->meta_dist_search();
  }
  if (defined $self->{soap}) {
    return 1 if $self->soap_dist_search();
  }
  if (HAS_CPAN) {
    return 1 if $self->cpan_dist_search();
  }
  return 1 if $self->ppd_dist_search();
  $ERROR = q{Not all query terms returned a result};
  return;
}

sub cpan_dist_search {
  my $self = shift;
  my @dists = @{$self->{todo}};
  my @todo = ();
  my $dist_id = $self->{dist_id};
  foreach my $d (@dists) {  
    my $query = $dist_id->{$d}
      || $self->guess_dist_from_mod($d)
	|| $self->dist_from_re($d);
    unless (defined $query) {
      push @todo, $d;
      next;
    }
    my $obj = CPAN::Shell->expand('Distribution', $query);
    unless (defined $obj) {
      push @todo, $d;
      next;
    }
    my $dists = {};
    my $string = $obj->as_string;
    my $cpan_file;
    if ($string =~ /id\s*=\s*(.*?)\n/m) {
      $cpan_file = $1;
      next unless $cpan_file;
    }
    my ($dist, $version) = file_to_dist($cpan_file);
    $dists->{dist_name} = $dist;
    $dists->{dist_file} = $cpan_file;
    $dists->{dist_vers} = $version;
    if ($string =~ /\s+CPAN_USERID.*\s+\((.*)\)\n/m) {
      $dists->{author} = $1;
      $dists->{cpanid} = $dists->{author};
    }
    $self->{dist_id}->{$dists->{dist_name}} ||=
      check_id($dists->{dist_file});
    my $mods;
    if ($string =~ /\s+CONTAINSMODS\s+(.*)/m) {
      $mods = $1;
    }
    next unless $mods;
    my @mods = split ' ', $mods;
    next unless @mods;
    (my $try = $dist) =~ s{-}{::}g;
    foreach my $mod(@mods) {
      my $module = CPAN::Shell->expand('Module', $mod);
      next unless $module;
      if ($mod eq $try) {
	my $desc = $module->description;
	$dists->{dist_abs} = $desc if $desc;
      }
      my $v = $module->cpan_version;
      $v = undef if $v eq 'undef';
      if ($v) {
	push @{$dists->{mods}}, {mod_name => $mod, mod_vers => $v};
      }
      else {
	push @{$dists->{mods}}, {mod_name => $mod};	
      }
    }
    $self->{dist_results}->{$dist} = $dists;
  }
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub meta_dist_search {
  my $self = shift;
  my @dists = @{$self->{todo}};
  my @todo = ();
  my $cpan_meta = $self->{cpan_meta};
  my $dist_id = $self->{dist_id};
  foreach my $d (@dists) {
    my $query = $dist_id->{$d};
    unless ((defined $query) or ($query = $self->guess_dist_from_mod($d))) {
      push @todo, $d;
      next;
    }
    my $id = $cpan_meta->instance('Distribution', $query);
    unless (defined $id) {
      push @todo, $d;
      next;
    }
    my $dists = {};
    my $string = $id->as_string;
    my $cpan_file;
    if ($string =~ /id\s*=\s*(.*?)\n/m) {
      $cpan_file = $1;
      next unless $cpan_file;
    }
    my ($dist, $version) = file_to_dist($cpan_file);
    $dists->{dist_name} = $dist;
    $dists->{dist_file} = $cpan_file;
    $dists->{dist_vers} = $version;
    if ($string =~ /\s+CPAN_USERID.*\s+\((.*)\)\n/m) {
      $dists->{author} = $1;
      $dists->{cpanid} = $dists->{author};
    }
    $self->{dist_id}->{$dists->{dist_name}} ||=
      check_id($dists->{dist_file});
    my $mods;
    if ($string =~ /\s+CONTAINSMODS\s+(.*)/m) {
      $mods = $1;
    }
    next unless $mods;
    my @mods = split ' ', $mods;
    next unless @mods;
    (my $try = $dist) =~ s{-}{::}g;
    foreach my $mod(@mods) {
      my $module = $cpan_meta->instance('Module', $mod);
      next unless $module;
      if ($mod eq $try) {
	my $desc = $module->description;
	$dists->{dist_abs} = $desc if $desc;
      }
      my $v = $module->cpan_version;
      $v = undef if $v eq 'undef';
      my $dist_name = file_to_dist($mod->cpan_file);
      if ($v) {
	push @{$dists->{mods}}, {mod_name => $mod, mod_vers => $v};
      }
      else {
	push @{$dists->{mods}}, {mod_name => $mod};	
      }
    }
    $self->{dist_results}->{$dist} = $dists;
  }
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub ppd_dist_search {
  my $self = shift;
  my @dists = @{$self->{todo}};
  my @todo = ();
  foreach my $dist (@dists) {
    my $content = get($meta . $dist . '/META.ppd');
    unless (defined $content and $content =~ /xml version/) {
      push @todo, $dist;
      next;
    }
    my $d = parse_ppd($content);
    my $info = {};
    $info->{dist_abs} = $d->{ABSTRACT};
    $info->{dist_name} = $d->{SOFTPKG}->{NAME};
    $info->{dist_vers} = $d->{SOFTPKG}->{VERSION};
    my $author = $d->{AUTHOR};
    $author =~ s/&lt;/</;
    $author =~ s/&gt;/>/;
    $info->{author} = $author;
    (my $cpanfile = $d->{CODEBASE}->{HREF}) =~ s{$meta/cpan/authors/id/}{};
    (my $cpanid = $cpanfile) =~ s{\w/\w\w/(\w+)/.*}{$1};
    $info->{cpanid} = $cpanid;
    $info->{dist_file} = $cpanfile;
    my $provide = $d->{PROVIDE};
    foreach my $item (@$provide) {
      my $v = $item->{VERSION};
      my $mod = $item->{NAME};
      if (defined $v) {
	push @{$info->{mods}}, {mod_name => $mod, mod_vers => $v};
      }
      else {
	push @{$info->{mods}}, {mod_name => $mod};	
      }
    }
    $self->{dist_results}->{$dist} = $info;
    $self->{dist_id}->{$info->{dist_name}} ||=
      check_id($info->{dist_file});
  }
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub soap_dist_search {
  my $self = shift;
  my $soap = $self->{soap};
  my $query = $self->{todo};
  my %dists = map {$_ => 1} @{$query};
  my $result = $soap->dist_info($query);
  eval {$result->fault};
  if ($@) {
      $ERROR = $@;
      return;
  }
  $result->fault and do {
    $ERROR = join ', ', 
      $result->faultcode, 
        $result->faultstring;
    return;
  };
  my $results = $result->result();
  return unless ($results);
  if (ref($query) eq 'ARRAY') {
    foreach my $entry (keys %$results) {
      delete $dists{$entry} if (defined $dists{$entry});
      my $info = $results->{$entry};
      my $email = $info->{email} || $info->{cpanid} . '@cpan.org';
      $info->{author} = $info->{fullname} . qq{ <$email> };
      (my $prefix = $info->{cpanid}) =~ s{^(\w)(\w)(\w+)}{$1/$1$2/$1$2$3};
      $info->{dist_file} = $prefix . '/' . $info->{dist_file};
      $self->{dist_results}->{$entry} = $info;
      $self->{dist_id}->{$info->{dist_name}} ||=
	check_id($info->{dist_file});
    }
  }
  else {
    my $email = $results->{email} || $results->{cpanid} . '@cpan.org';
    my $dist_name = $results->{dist_name};
    $results->{author} = $results->{fullname} . qq{ <$email>};
    (my $prefix = $results->{cpanid}) =~ s{^(\w)(\w)(\w+)}{$1/$1$2/$1$2$3};
    $results->{dist_file} = $prefix . '/' . $results->{dist_file};
    $self->{dist_results}->{$dist_name} = $results;
    $self->{dist_id}->{$results->{dist_name}} ||=
      check_id($results->{dist_file});
    delete $dists{$dist_name} if (defined $dists{$dist_name});
  }
  my @todo = keys %dists;
  if (scalar @todo > 0) {
    $self->{todo} = \@todo;
    return;
  }
  $self->{todo} = [];
  return 1;
}

sub guess_dist_from_mod {
  my ($self, $dist) = @_;
  my $query_save = $self->{query};
  my $args_save = $self->{args};
  my $todo_save = $self->{todo};
  (my $try = $dist) =~ s{-}{::}g;
  my $dist_file = '';
  if ($self->search($try, mode => 'mod')) {
    $dist_file = $self->{mod_results}->{$try}->{dist_file};
  }
  $self->{query} = $query_save;
  $self->{args} = $args_save;
  $self->{todo} = $todo_save;
  return check_id($dist_file);
}

sub dist_from_re {
  my ($self, $d) = @_;
  foreach my $match (CPAN::Shell->expand('Distribution', qq{/$d/})) {
    my $string = $match->as_string;
    my $cpan_file;
    if ($string =~ /id\s*=\s*(.*?)\n/m) {
      $cpan_file = $1;
      next unless $cpan_file;
    }
    my $dist = file_to_dist($cpan_file);
    if ($dist eq $d) {
      return check_id($cpan_file);
    }
  }
  return;
}

sub search_error {
  my $self = shift;
  warn $ERROR;
}

sub check_id {
  my $dist_file = shift;
  if ($dist_file =~ m{^\w/\w\w/}) {
    $dist_file =~ s{^\w/\w\w/}{};
  }
  return $dist_file;
}

1;

__END__


=head1 NAME

  PPM::Make::Search - search for info to make ppm packages

=head1 SYNOPSIS

  use PPM::Make::Search;
  my $search = PPM::Make::Search->new();

  my @query = qw(Net::FTP Math::Complex);
  $search->search(\@query, mode => 'mod') or $search->search_error();
  my $results = $search->{mod_results};
  # print results

=head1 DESCRIPTION

This module either queries a remote SOAP server (if
L<SOAP::Lite> is available), uses L<CPAN.pm>, if
configured, or uses L<LWP::Simple> for a connection
to L<http://cpan.uwinnipeg.ca/> to provide information on 
either modules or distributions needed to make a ppm package.
The basic object is created as

  my $search = PPM::Make::Search->new();

with searches being performed as

  my @query = qw(Net::FTP Math::Complex);
  $search->search(\@query, mode => 'mod') or $search->search_error();

The first argument to the C<search> method is either a
string containing the name of the module or distribution,
or else an array reference containing module or distribution
names. The results are contained in C<$search-E<gt>{mod_results}>,
for module queries, or C<$search-E<gt>{dist_results}>,
for distribution queries. Supported values of C<mode> are

=over

=item C<mode =E<gt> 'mod'>

This is used to search for modules.
The query term must match exactly, in a case
sensitive manner. The results are returned as a hash reference,
the keys being the module name, and the associated values
containing the information in the form:

  my @query = qw(Net::FTP Math::Complex);
  $search->search(\@query, mode => 'mod') or $search->search_error();
  my $results = $search->{mod_results};
  foreach my $m(keys %$results) {
    my $info = $results->{$m};
    print <<"END"
  For module $m:
   Module: $info->{mod_name}
    Version: $info->{mod_vers}
    Description: $info->{mod_abs}
    Author: $info->{author}
    CPANID: $info->{cpanid}
    CPAN file: $info->{dist_file}
    Distribution: $info->{dist_name}
  END
  }

=item C<mode =E<gt> 'dist'>

This is used to search for distributions.
The query term must match exactly, in a case
sensitive manner. The results are returned as a hash reference,
the keys being the distribution name, and the associated values
containing the information in the form:

  my @d = qw(Math-Complex libnet);
  $search->search(\@d, mode => 'dist') or $search->search_error();
  my $results = $search->{dist_results};
  foreach my $d(keys %$results) {
    my $info = $results->{$d};
    print <<"END";
   For distribution $d:
    Distribution: $info->{dist_name}
    Version: $info->{dist_vers}
    Description: $info->{dist_abs}
    Author: $info->{author}
    CPAN file: $info->{dist_file}
  END
    my @mods = @{$info->{mods}};
    foreach (@mods) {
      print "Contains module $_->{mod_name}: Version: $_->{mod_vers}\n";
    }
  }

=back

=head1 COPYRIGHT

This program is copyright, 2008 by
Randy Kobes E<lt>r.kobes@uwinnipeg.caE<gt>.
It is distributed under the same terms as Perl itself.

=head1 SEE ALSO

L<PPM>.

=cut

