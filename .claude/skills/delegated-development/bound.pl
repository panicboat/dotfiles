#!/usr/bin/perl
use strict;
use warnings;
use POSIX ();

sub usage {
    print STDERR "usage: bound.pl <seconds> <command> [args...]\n";
    exit 2;
}

sub exit_code {
    my ($status) = @_;
    my $signal = $status & 127;
    return $signal ? 128 + $signal : $status >> 8;
}

# Walk pgrep -P instead of killing a process group: codex starts tool commands in their own groups.
sub descendants {
    my ($pid) = @_;
    open(my $fh, '-|', 'pgrep', '-P', $pid) or do { warn "bound.pl: pgrep: $!\n"; return () };
    my @children = map { chomp; $_ } <$fh>;
    close $fh;
    return map { ($_, descendants($_)) } @children;
}

my ($seconds, @command) = @ARGV;
usage() unless defined $seconds && $seconds =~ /^[0-9]+$/ && $seconds > 0 && @command;

my $pid = fork();
die "bound.pl: fork: $!\n" unless defined $pid;
if ($pid == 0) {
    no warnings 'exec';
    exec { $command[0] } @command or do {
        warn "bound.pl: $command[0]: $!\n";
        POSIX::_exit(127);
    };
}

# The handler dies because perl restarts waitpid after EINTR, so a flag would never be seen.
my $finished = eval {
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm $seconds;
    waitpid($pid, 0) == $pid or die "bound.pl: waitpid: $!\n";
    alarm 0;
    1;
};
exit exit_code($?) if $finished;
die $@ unless $@ eq "timeout\n";

exit exit_code($?) if waitpid($pid, POSIX::WNOHANG()) == $pid;

my @targets = ($pid, descendants($pid));
kill 'TERM', @targets;
sleep 2;
kill 'KILL', @targets;
exit 142;
