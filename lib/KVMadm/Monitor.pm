package KVMadm::Monitor;

use strict;
use warnings;

use IO::Socket::INET;
use IO::Socket::UNIX qw(SOCK_STREAM);
use IO::Select;

# globals
my @MON_INFO    = qw(block blockstats chardev cpus kvm network pci registers qtree usb version vnc);
my $RCV_TMO     = 3;

# constructor
sub new {
    my $class = shift;
    my $self = { @_ };

    return bless $self, $class
}

sub monInfo {
    my $self = shift;

    return [ @MON_INFO ];
}

sub queryMonitor {
    my $self  = shift;
    my $sock  = shift;
    my $query = shift;

    my $socket = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Peer => $sock,
    ) or die "Cannot open socket $!\n";

    $socket->send($query);

    my $wait = IO::Select->new;
    $wait->add($socket);
    
    my $recv;
    while ($wait->can_read($RCV_TMO)){
        my $buffer;

        defined $socket->recv($buffer, 1024) or die "ERROR: cannot read from monitor: $!\n";
        $recv .= $buffer;

        last if $recv =~ s/\(qemu\)/\(qemu\)/g == 2;
    }
    $socket->close();
    return [ grep { $_ !~ /^(?:QEMU|\(qemu\))/ } split "\n", $recv ];
}

sub soCat {
    my $self = shift;
    my $sock = shift;
    my $host = shift;

    my ($ip, $port) = $host =~ /^(?:(\d{1,3}(?:\.\d{1,3}){3}):)?(\d+)$/i;
    $ip //= '0.0.0.0';
    $port or die "ERROR: port $port not valid\n";

    my $iosel = IO::Select->new;
    my %connection = ();
    my $socket;
    my $client;
    my $server = IO::Socket::INET->new(
        LocalAddr => $ip,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => 1,
    ) or die "ERROR: cannot listen on $ip:$port: $!\n";
    $iosel->add($server);

    print "Listening on $ip:$port...\n";

    while (1){
        for my $ready ($iosel->can_read){
            if ($ready == $server){
                $socket = IO::Socket::UNIX->new(
                    Type => SOCK_STREAM,
                    Peer => $sock,
                ) or die "ERROR: cannot open socket $sock: $!\n";
                $iosel->add($socket);

                $client = $server->accept;
                $iosel->add($client);
                $connection{$client} = $socket;
                $connection{$socket} = $client;
            }
            else{
                next if !exists $connection{$ready};
                my $buffer;
                if ($ready->sysread($buffer, 4096)){
                    $connection{$ready}->syswrite($buffer);
                }
                else{
                    $iosel->remove($client);
                    $iosel->remove($socket);
                    %connection = ();

                    $client->close;
                    $socket->close;
                }
            }
        }
    }
}

sub sockConn {
    my $self = shift;
    my $sock = shift;

    local $| = 1;

    my $iosel = IO::Select->new;
    $iosel->add(\*STDIN);

    my $socket = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Peer => $sock,
    ) or die "ERROR: cannot open socket $sock: $!\n";
    $iosel->add($socket);

    while (1){
        for my $ready ($iosel->can_read){
            if ($ready == $socket){
                my $buffer;
                if ($socket->sysread($buffer, 1024)){
                    print $buffer;
                }
            }
            elsif ($ready == \*STDIN){
                my $buffer;
                $ready->sysread($buffer, 1024);
                $socket->syswrite($buffer);
            }
            else{
                $socket->close;
                exit;
            }
        }
    }
}

1;

