use strict;
use warnings;
package AnyEvent::RFXCOM::RX;

# ABSTRACT: AnyEvent::RFXCOM::RX module for an RFXCOM receiver

=head1 SYNOPSIS

  # Create simple RFXCOM message reader with logging callback
  my $rx =
     AnyEvent::RFXCOM::RX->new(callback => sub { print $_[0]->summary },
                               device => '/dev/ttyUSB0');

  # initiate connection to device
  my $cv = $rx->start;

  # wait for it to complete (optional)
  $cv->recv;

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
use Device::RFXCOM::RX;
use Carp qw/croak/;
use Try::Tiny;

sub new {
  my ($pkg, %p) = @_;
  my $self = $pkg->SUPER::new(%p);
  croak $pkg.'->new: callback parameter is required' unless ($self->{callback});
  $self;
}

sub start {
  my $self = shift;
  croak((ref $self).'->start called twice') if ($self->{handle});
  my $user_cv = AnyEvent->condvar;
  my $cv = AnyEvent->condvar;
  $cv->cb(sub {
            my $fh = $_[0]->recv;
            print STDERR "start cb @_\n" if DEBUG;
            my $hd = $self->{handle} =
              AnyEvent::Handle->new(
                                    fh => $fh,
                                    on_error => sub {
                                      my ($handle, $fatal, $msg) = @_;
                                      print STDERR "handle error $msg\n"
                                        if DEBUG;
                                      $handle->destroy;
                                      if ($fatal) {
                                        $self->cleanup($msg);
                                      }
                                    },
                                    on_eof   => sub {
                                      my ($handle) = @_;
                                      print STDERR "handle eof\n" if DEBUG;
                                      $handle->destroy;
                                      $self->cleanup('connection closed');
                                    },
                                   );
            $self->{handle}->push_write(pack 'H*', 'F020');
            $self->{_waiting} = 1;
            $self->{handle}->push_read(ref $self => $self,
              sub {
                $self->{handle}->push_write(pack 'H*', 'F041');
                $self->{_waiting} = 1;
                $self->{handle}->push_read(ref $self => $self,
                  sub {
                    $self->{handle}->push_write(pack 'H*', 'F02A');
                    $self->{_waiting} = 1;
                    $self->{handle}->push_read(ref $self => $self,
                      sub {
                        $self->{callback}->(@_);
                        return;
                      });
                    $self->{callback}->(@_);
                    return 1;
                  });
                $self->{callback}->(@_);
                return 1;
              });
            $user_cv->send(1);
          });
  $self->_open($cv);
  return $user_cv;
}

sub cleanup {
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

sub anyevent_read_type {
  my ($handle, $cb, $self) = @_;

  my $cache = {};
  sub {
    my $rbuf = \$handle->{rbuf};
  REDO:
    print STDERR "Before: ", (unpack 'H*', $$rbuf||''), "\n" if DEBUG;
    my $res = $self->read_one($rbuf) or return;
    print STDERR "After: ", (unpack 'H*', $$rbuf), "\n" if DEBUG;
    $res = $cb->($res) and return $res;
    goto REDO;
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
