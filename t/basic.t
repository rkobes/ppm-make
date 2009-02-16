#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
BEGIN {plan tests => 9};
for (qw(PPM::Make PPM::Make::Util PPM::Make::Install PPM::Make::Config
       PPM::Make::RepositorySummary PPM::Make::Meta PPM::Make::Bundle
       PPM::Make::Search PPM::Make::CPAN)) {
  require_ok($_);
}
