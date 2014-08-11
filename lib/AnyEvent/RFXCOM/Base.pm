use strict;
use warnings;
package AnyEvent::RFXCOM::Base;

# ABSTRACT: module for AnyEvent RFXCOM base class

=head1 SYNOPSIS

  # ... abstract base class

=head1 DESCRIPTION

Module for AnyEvent RFXCOM base class.

=cut

use 5.006;
use constant {
  DEBUG => $ENV{ANYEVENT_RFXCOM_BASE_DEBUG},
};

use AnyEvent::Handle;
use AnyEvent::Socket;
use Sub::Name;
use Scalar::Util qw/weaken/;

sub _open_condvar {
  my $self = shift;
  my $cv = AnyEvent->condvar;
  my $weak_self = $self;
  weaken $weak_self;

  $cv->cb(subname 'open_cb' => sub {
            my $fh = $_[0]->recv;
            print STDERR "start cb $fh @_\n" if DEBUG;
            my $handle; $handle =
              AnyEvent::Handle->new(
                fh => $fh,
                on_error => subname('on_error' => sub {
                  my ($handle, $fatal, $msg) = @_;
                  print STDERR $handle.": error $msg\n" if DEBUG;
                  $handle->destroy;
                  if ($fatal && defined $weak_self) {
                    $weak_self->cleanup($msg);
                  }
                }),
                on_eof => subname('on_eof' => sub {
                  my ($handle) = @_;
                  print STDERR $handle.": eof\n" if DEBUG;
                  $weak_self->cleanup('connection closed');
                }),
              );
            $weak_self->{handle} = $handle;
            $weak_self->_handle_setup();
            delete $weak_self->{_waiting}; # uncork queued writes
            $weak_self->_write_now();
          });
  $weak_self->{_waiting} = { desc => 'fake for async open' };
  return $cv;
}

=method C<cleanup()>

This method attempts to destroy any resources in the event of a
disconnection or fatal error.

=cut

sub cleanup {
  my $self = shift;
  print STDERR $self."->cleanup\n" if DEBUG;
  $self->{handle}->destroy if ($self->{handle});
  delete $self->{handle};
}

sub _open_tcp_port {
  my ($self, $cv) = @_;
  my $dev = $self->{device};
  print STDERR "Opening $dev as tcp socket\n" if DEBUG;
  require AnyEvent::Socket; import AnyEvent::Socket;
  my ($host, $port) = split /:/, $dev, 2;
  $port = $self->{port} unless (defined $port);
  $self->{sock} = tcp_connect $host, $port, subname 'tcp_connect_cb' => sub {
    my $fh = shift
      or do {
        my $err = (ref $self).": Can't connect to device $dev: $!";
        $self->cleanup($err);
        $cv->croak($err);
      };

    warn "Connected\n" if DEBUG;
    $cv->send($fh);
  };
  return $cv;
}

sub _real_write {
  my ($self, $rec) = @_;
  print STDERR "Sending: ", $rec->{hex}, ' ', ($rec->{desc}||''), "\n" if DEBUG;
  $self->{handle}->push_write($rec->{raw});
  $rec->{cv}->begin if ($rec->{cv});
}

sub _time_now {
  AnyEvent->now;
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
