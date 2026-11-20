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

sub terminate_tree {
    my ($pid) = @_;
    alarm 0;
    # A second signal must not interrupt the sweep, or the tree is orphaned.
    $SIG{$_} = 'IGNORE' for qw(HUP INT TERM);
    my @targets = ($pid, descendants($pid));
    kill 'TERM', @targets;
    sleep 2;
    kill 'KILL', @targets;
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

my %signal_number = (HUP => 1, INT => 2, TERM => 15);
for my $name (keys %signal_number) {
    $SIG{$name} = sub { terminate_tree($pid); exit 128 + $signal_number{$name} };
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

terminate_tree($pid);
exit 142;
