use strict;
use warnings;
package AnyEvent::RFXCOM::RX;

# ABSTRACT: AnyEvent::RFXCOM::RX module for an RFXCOM receiver

=head1 SYNOPSIS

  # Create simple RFXCOM message reader with logging callback
  AnyEvent::RFXCOM::RX->new(callback => sub { print $_[0]->summary },
                            device => '/dev/ttyUSB0');

  # start event loop
  AnyEvent->condvar->recv;

=head1 DESCRIPTION

AnyEvent module for handling communication with an RFXCOM receiver.

=cut

use 5.010;
use constant DEBUG => $ENV{ANYEVENT_RFXCOM_RX_DEBUG};
use base 'Device::RFXCOM::RX';
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Carp qw/croak/;

=method C<new(%params)>

Constructs a new C<AnyEvent::RFXCOM::RX> object.  The supported
parameters are:

=over

=item device

The name of the device to connect to.  The value can be a tty device
name or a C<hostname:port> for TCP-based RFXCOM receivers.  The
default is C</dev/rfxcom-rx>.  See C<Device::RFXCOM::RX> for more
information.

=item callback

The callback to execute when a message is received.

=back

=cut

sub new {
  my ($pkg, %p) = @_;
  croak $pkg.'->new: callback parameter is required' unless ($p{callback});
  my $self = $pkg->SUPER::new(%p);
  $self;
}

sub _open {
  my $self = shift;
  my $cv = AnyEvent->condvar;
  $cv->cb(sub {
            my $fh = $_[0]->recv;
            print STDERR "start cb @_\n" if DEBUG;
            my $handle; $handle =
              AnyEvent::Handle->new(
                fh => $fh,
                on_error => sub {
                  my ($handle, $fatal, $msg) = @_;
                  print STDERR $handle.": error $msg\n" if DEBUG;
                  $handle->destroy;
                  if ($fatal) {
                    $self->cleanup($msg);
                  }
                },
                on_eof => sub {
                  my ($handle) = @_;
                  print STDERR $handle.": eof\n" if DEBUG;
                  $handle->destroy;
                  $self->cleanup('connection closed');
                },
                on_rtimeout => sub {
                  my $rbuf = \$handle->{rbuf};
                  print STDERR $handle, ": discarding '",
                    (unpack 'H*', $$rbuf), "'\n" if DEBUG;
                  $$rbuf = '';
                  $handle->rtimeout(0);
                },
                on_timeout => sub {
                  print STDERR $handle.": Clearing duplicate cache\n" if DEBUG;
                  $self->{_cache} = {};
                  $handle->timeout(0);
                },
              );
            $self->{handle} = $handle;
            $handle->push_read(ref $self => $self,
                               sub {
                                 $self->{callback}->(@_);
                                 $self->_write_now();
                                 return;
                               });
            undef $self->{_waiting}; # uncork queued writes
            $self->_write_now();
          });
  $self->{_waiting} = { desc => 'fake for async open' };
  $self->SUPER::_open($cv);
  return 1;
}

sub _real_write {
  my ($self, $rec) = @_;
  print STDERR "Sending: ", $rec->{hex}, ' ', ($rec->{desc}||''), "\n" if DEBUG;
  $self->{handle}->push_write($rec->{raw});
}

sub DESTROY {
  $_[0]->cleanup;
}

=method C<cleanup()>

This method attempts to destroy any resources in the event of a
disconnection or fatal error.  It is not yet implemented.

=cut

sub cleanup {
  my ($self, $error) = @_;
  print STDERR $self."->cleanup\n" if DEBUG;
  undef $self->{discard_timer};
  undef $self->{dup_timer};
}

sub _open_serial_port {
  my ($self, $cv) = @_;
  my $fh = $self->SUPER::_open_serial_port;
  $cv->send($fh);
  return $cv;
}

sub _open_tcp_port {
  my ($self, $cv) = @_;
  my $dev = $self->{device};
  print STDERR "Opening $dev as tcp socket\n" if DEBUG;
  require AnyEvent::Socket; import AnyEvent::Socket;
  my ($host, $port) = split /:/, $dev, 2;
  $port = $self->{port} unless (defined $port);
  $self->{sock} = tcp_connect $host, $port, sub {
    my $fh = shift
      or do {
        my $err = (ref $self).": Can't connect RFXCOM device $dev: $!";
        $self->cleanup($err);
        $cv->croak($err);
      };

    warn "Connected\n" if DEBUG;
    $cv->send($fh);
  };
  return $cv;
}

sub _time_now {
  AnyEvent->now;
}

=method C<anyevent_read_type()>

This method is used to register an L<AnyEvent::Handle> read type
method to read RFXCOM messages.

=cut

sub anyevent_read_type {
  my ($handle, $cb, $self) = @_;

  sub {
    my $rbuf = \$handle->{rbuf};
    $handle->rtimeout($self->{discard_timeout});
    $handle->timeout($self->{dup_timeout});
    while (1) { # read all message from the buffer
      print STDERR "Before: ", (unpack 'H*', $$rbuf||''), "\n" if DEBUG;
      my $res = $self->read_one($rbuf);
      unless ($res) {
        if (defined $res) {
          print STDERR "Ignoring duplicate\n" if DEBUG;
          next;
        }
        return;
      }
      print STDERR "After: ", (unpack 'H*', $$rbuf), "\n" if DEBUG;
      $res = $cb->($res) and return $res;
    }
  }
}

1;

=head1 THANKS

Special thanks to RFXCOM, L<http://www.rfxcom.com/>, for their
excellent documentation and for giving me permission to use it to help
me write this code.  I own a number of their products and highly
recommend them.

=head1 SEE ALSO

AnyEvent(3)

RFXCOM website: http://www.rfxcom.com/
