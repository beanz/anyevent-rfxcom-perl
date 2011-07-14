
use strict;
use warnings;

BEGIN { require 5.008; }

use ExtUtils::MakeMaker 6.31;



my %WriteMakefileArgs = (
  'ABSTRACT' => 'Perl modules for RFXCOM RF receivers/transmitters with AnyEvent',
  'AUTHOR' => 'Mark Hindess <soft-cpan@temporalanomaly.com>',
  'BUILD_REQUIRES' => {
    'AnyEvent::MockTCPServer' => '0',
    'English' => '0',
    'Test::More' => '0'
  },
  'CONFIGURE_REQUIRES' => {
    'ExtUtils::MakeMaker' => '6.31'
  },
  'DISTNAME' => 'AnyEvent-RFXCOM',
  'EXE_FILES' => [
    'bin/rfxcom-anyevent-rx',
    'bin/w800-anyevent-rx',
    'bin/rfxcom-anyevent-tx'
  ],
  'LICENSE' => 'perl',
  'NAME' => 'AnyEvent::RFXCOM',
  'PREREQ_PM' => {
    'AnyEvent' => '5.271',
    'AnyEvent::Handle' => '0',
    'AnyEvent::Socket' => '0',
    'Carp' => '0',
    'Device::RFXCOM::Base' => '1.103250',
    'Device::RFXCOM::RX' => '0',
    'Device::RFXCOM::TX' => '0',
    'Device::W800' => '0',
    'Scalar::Util' => '0',
    'Sub::Name' => '0',
    'constant' => '0'
  },
  'VERSION' => '1.111950',
  'test' => {
    'TESTS' => 't/*.t'
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



