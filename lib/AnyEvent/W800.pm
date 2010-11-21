use strict;
use warnings;
package AnyEvent::W800;

# ABSTRACT: Module to support W800 RF receiver

=head1 SYNOPSIS

  # Create simple W800 message reader with logging callback
  AnyEvent::W800->new(callback => sub { print $_[0]->summary },
                      device => '/dev/ttyUSB0');

  # start event loop
  AnyEvent->condvar->recv;

=head1 DESCRIPTION

AnyEvent module to decode messages from an W800 RF receiver from WGL &
Associates.

B<IMPORTANT:> This API is still subject to change.

=cut

use 5.006;
use constant DEBUG => $ENV{ANYEVENT_W800_DEBUG};
use Carp qw/croak/;
use base qw/AnyEvent::RFXCOM::Base Device::W800/;

=method C<new(%parameters)>

This constructor returns a new W800 RF receiver object.  The only
supported parameter is:

=over

=item device

The name of the device to connect to.  The value can be a tty device
name or a C<hostname:port> for TCP-based serial port redirection.

The default is C</dev/w800> in anticipation of a scenario where a udev
rule has been used to identify the USB tty device of the W800.

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
    $handle->on_rtimeout(sub {
    my $rbuf = \$handle->{rbuf};
    print STDERR $handle, ": discarding '",
      (unpack 'H*', $$rbuf), "'\n" if DEBUG;
    $$rbuf = '';
    $handle->rtimeout(0);
  });
  $handle->on_timeout(sub {
    print STDERR $handle.": Clearing duplicate cache\n" if DEBUG;
    $self->{_cache} = {};
    $handle->timeout(0);
  });
  $handle->push_read(ref $self => $self,
                     sub {
                       $self->{callback}->(@_);
                       $self->_write_now();
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
  print STDERR $self."->cleanup\n" if DEBUG;
  undef $self->{discard_timer};
  undef $self->{dup_timer};
}

=method C<anyevent_read_type()>

This method is used to register an L<AnyEvent::Handle> read type
method to read W800 messages.

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

=head1 SEE ALSO

L<Device::W800>

W800 website: http://www.wgldesigns.com/w800.html
