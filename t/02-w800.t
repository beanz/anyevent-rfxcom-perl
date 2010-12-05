#!/usr/bin/perl
#
# Copyright (C) 2010 by Mark Hindess

use strict;
use warnings;
use constant {
  DEBUG => $ENV{ANYEVENT_W800_TEST_DEBUG}
};

$|=1;

BEGIN {
  require Test::More;
  eval { require AnyEvent; import AnyEvent;
         require AnyEvent::Handle; import AnyEvent::Handle;
         require AnyEvent::Socket; import AnyEvent::Socket };
  if ($@) {
    import Test::More skip_all => 'Missing AnyEvent module(s): '.$@;
  }
  import Test::More;
  use t::Helpers qw/:all/;
}

my @connections =
  (
   [
    {
     desc => 'partial message',
     send => '609f08',
    },
    {
     desc => 'sleep 1',
     sleep => 0.3,
    },
    {
     desc => 'rest of message',
     send => 'f7',
    },
    {
     desc => 'complete message',
     send => '609f08f7',
    },
    {
     desc => 'sleep 2',
     sleep => 0.3,
    },
   ],
  );

my $cv = AnyEvent->condvar;
my $server;
eval { $server = test_server($cv, @connections) };
plan skip_all => "Failed to create dummy server: $@" if ($@);

my ($host,$port) = @{$cv->recv};
my $addr = join ':', $host, $port;

plan tests => 24;

use_ok('AnyEvent::W800');

$cv = AnyEvent->condvar;

my @tests =
  (
   sub {
     my ($res) = @_;
     is($res->type, 'x10', 'got x10 message');
     is($res->header_byte, 0x20, '... correct header_byte');
     ok($res->master, '... from master receiver');
     is($res->length, 4, '... correct data length');
     is($res->hex_data, '609f08f7', '... correct data');
     is($res->summary,
        'master x10 20.609f08f7: x10/a3/on',
        '... correct summary string');

     is(scalar @{$res->messages}, 1, '... correct number of messages');
     my $message = $res->messages->[0];
     is($message->type, 'x10', '... correct message type');
     is($message->command, 'on', '... correct message command');
     is($message->device, 'a3', '... correct message device');
   },
   sub {
     my ($res) = @_;
     ok($res->duplicate, '... received a duplicate');
     is($res->type, 'x10', 'got x10 message');
     is($res->header_byte, 0x20, '... correct header_byte');
     ok($res->master, '... from master receiver');
     is($res->length, 4, '... correct data length');
     is($res->hex_data, '609f08f7', '... correct data');
     is($res->summary,
        'master x10 20.609f08f7(dup): x10/a3/on',
        '... correct summary string');

     is(scalar @{$res->messages}, 1, '... correct number of messages');
     my $message = $res->messages->[0];
     is($message->type, 'x10', '... correct message type');
     is($message->command, 'on', '... correct message command');
     is($message->device, 'a3', '... correct message device');
     $cv->send(1);
   },
  );

my $w800 = AnyEvent::W800->new(device => $addr,
                               callback => sub { (shift@tests)->(@_); 1; },
                               discard_timeout => 0.4);

ok($w800, 'instantiate AnyEvent::W800 object');

$cv->recv;

undef $server;
undef $w800;

SKIP: {
  skip 'fails with some event loops', 1
    unless ($AnyEvent::MODEL eq 'AnyEvent::Impl::Perl');

  $cv = AnyEvent->condvar;
  AnyEvent::W800->new(device => $addr, callback => sub {});
  eval { $cv->recv };
  like($@, qr!^AnyEvent::W800: Can't connect to device \Q$addr\E:!o,
       'connection failed');
}
