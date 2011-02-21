use strict;
use warnings;
package AnyEvent::RFXCOM::RX;

# ABSTRACT: AnyEvent module for an RFXCOM receiver

=head1 SYNOPSIS

  # Create simple RFXCOM message reader with logging callback
  AnyEvent::RFXCOM::RX->new(callback => sub { print $_[0]->summary },
                            device => '/dev/ttyUSB0');

  # start event loop
  AnyEvent->condvar->recv;

=head1 DESCRIPTION

AnyEvent module for handling communication with an RFXCOM receiver.

=cut

use 5.008;
use constant DEBUG => $ENV{ANYEVENT_RFXCOM_RX_DEBUG};
use base qw/AnyEvent::RFXCOM::Base Device::RFXCOM::RX/;
use AnyEvent;
use Carp qw/croak/;
use Sub::Name;
use Scalar::Util qw/weaken/;

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

sub _handle_setup {
  my $self = shift;
  my $handle = $self->{handle};
  my $weak_self = $self;
  weaken $weak_self;
  $handle->on_rtimeout(subname 'on_rtimeout_cb' => sub {
    my ($handle) = @_;
    my $rbuf = \$handle->{rbuf};
    print STDERR $handle, ": discarding '",
      (unpack 'H*', $$rbuf), "'\n" if DEBUG;
    $$rbuf = '';
    $handle->rtimeout(0);
  });
  $handle->on_timeout(subname 'on_timeout_cb' => sub {
    my ($handle) = @_;
    print STDERR $handle.": Clearing duplicate cache\n" if DEBUG;
    $weak_self->{_cache} = {};
    $handle->timeout(0);
  });
  $handle->push_read(ref $self => $self,
                     subname 'push_read_cb' => sub {
                       $weak_self->{callback}->(@_);
                       $weak_self->_write_now();
                       return;
                     });
  1;
}

sub _open {
  my $self = shift;
  $self->SUPER::_open($self->_open_condvar);
  return 1;
}

sub _open_serial_port {
  my ($self, $cv) = @_;
  my $fh = $self->SUPER::_open_serial_port;
  $cv->send($fh);
  return $cv;
}

sub DESTROY {
  $_[0]->cleanup;
}

=method C<cleanup()>

This method attempts to destroy any resources in the event of a
disconnection or fatal error.

=cut

sub cleanup {
  my ($self, $error) = @_;
  $self->SUPER::cleanup(@_);
  undef $self->{discard_timer};
  undef $self->{dup_timer};
}

=method C<anyevent_read_type()>

This method is used to register an L<AnyEvent::Handle> read type
method to read RFXCOM messages.

=cut

sub anyevent_read_type {
  my ($handle, $cb, $self) = @_;

  my $weak_self = $self;
  weaken $weak_self;

  subname 'anyevent_read_type_reader' => sub {
    my ($handle) = @_;
    my $rbuf = \$handle->{rbuf};
    $handle->rtimeout($weak_self->{discard_timeout});
    $handle->timeout($weak_self->{dup_timeout});
    while (1) { # read all message from the buffer
      print STDERR "Before: ", (unpack 'H*', $$rbuf||''), "\n" if DEBUG;
      my $res = $weak_self->read_one($rbuf);
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
