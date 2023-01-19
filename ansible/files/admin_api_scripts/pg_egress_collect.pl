#!/usr/bin/env perl

# This script receive tcpdump output through STDIN and does:
#
# 1. extract outgoing TCP packet length on all devices port 5432 and 6543
# 2. sum the length up to one minute
# 3. save the total length to file (default is /tmp/pg_egress_collect.txt) per minute
#
# Usage:
#
# tcpdump -s 128 -Q out -i any -nn -tt -vv -p -l 'tcp and (port 5432 or port 6543)' | perl pg_egress_collect.pl /tmp/output.txt
#

use POSIX;
use List::Util qw(sum);
use IO::Async::Loop;
use IO::Async::Stream;
use IO::Async::Timer::Periodic;

use strict;
use warnings;

# total captured packets lenth in a time frame
my $captured_len = 0;

# extract tcp packet length captured by tcpdump
#
# Sample input lines:
#
# 1674013833.940253 IP (tos 0x0, ttl 64, id 0, offset 0, flags [DF], proto TCP (6), length 60)
#     10.112.101.122.5432 > 220.235.16.223.62599: Flags [S.], cksum 0x5de3 (incorrect -> 0x63da), seq 2314200657, ack 2071735457, win 62643, options [mss 8961,sackOK,TS val 3358598837 ecr 1277499190,nop,wscale 7], length 0
# 1674013833.989257 IP (tos 0x0, ttl 64, id 24975, offset 0, flags [DF], proto TCP (6), length 52)
#     10.112.101.122.5432 > 220.235.16.223.62599: Flags [.], cksum 0x5ddb (incorrect -> 0xa25b), seq 1, ack 9, win 490, options [nop,nop,TS val 3358598885 ecr 1277499232], length 0
sub extract_packet_length {
    my ($line) = @_;

    #print("debug: >> " . $line);

    if ($line =~ /^(\d+)\.\d+/) {
        # extract packet timestamp, do nothing for now
        my $ts = $1;
    } elsif ($line =~ /^\s+\d+\.\d+\.\d+\.\d+\..*, length (\d+)$/) {
        # extract tcp packet length and add it up
        my $len = $1;
        $captured_len += $len;
    }
}

# write total length to file
sub write_file {
    my ($output) = @_;

    my $now = strftime "%F %T", localtime time;
    print "[$now] write captured len $captured_len to $output\n";

    open(my $fh, "+>", $output) or die "Could not open file '$output' $!";
    print $fh "$captured_len";
    close($fh);
}

# main
sub main {
    my ($output) = @ARGV;

    if (not defined $output) {
        # default output file path
        $output = "/tmp/pg_egress_collect.txt";
    }

    my $loop = IO::Async::Loop->new;

    # tcpdump extractor
    my $extractor = IO::Async::Stream->new_for_stdin(
        on_read => sub {
            my ($self, $buffref, $eof) = @_;

            while($$buffref =~ s/^(.*\n)//) {
                my $line = $1;
                extract_packet_length($line);
            }

            return 0;
        },
    );

    # schedule file writer per minute
    my $writer = IO::Async::Timer::Periodic->new(
        interval => 60,
        on_tick => sub {
            write_file($output);

            # reset total captured length
            $captured_len = 0;
        },
    );
    $writer->start;

    print "pg_egress_collect started, egress data will be saved to $output\n";

    $loop->add($extractor);
    $loop->add($writer);
    $loop->run;
}

main();

