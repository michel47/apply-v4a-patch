#!/usr/bin/perl
use strict;
use warnings;
use File::Copy     qw(copy);
use File::Path     qw(make_path);
use File::Basename qw(dirname);
use File::Temp     qw(tempfile);
use File::Spec     ();
use Getopt::Long   qw(GetOptions);
use POSIX          qw(strftime);

# ============== CLI ==============
my %opt = (dry_run => 0, backup => 0, help => 0, strict => 0, diff => 1, ellipsis => 0);

GetOptions(
    'dry-run|n'  => \$opt{dry_run},
    'backup|b'   => \$opt{backup},
    'strict'     => \$opt{strict},
    'diff!'      => \$opt{diff},       # --no-diff to disable
    'ellipsis'   => \$opt{ellipsis},
    'help|h'     => \$opt{help},
) or die "invalid options\n";

if ($opt{help} || @ARGV != 1) {
    print_usage();
    exit($opt{help} ? 0 : 2);
}

my $patch_path = shift @ARGV;

# ============== READ PATCH ==============
open(my $pfh, '<', $patch_path)
    or die "cannot open patch file '$patch_path': $!\n";
my @patch_lines = <$pfh>;
close $pfh;

s/\r\n/\n/g for @patch_lines;   # normalize line endings

# ============== PARSE ==============
my @ops = parse_v4a_patch(\@patch_lines);
die "no operations found in '$patch_path'\n" unless @ops;

# ============== APPLY ==============
my $errors = 0;
for my $op (@ops) {
    my $ok = eval { apply_v4a_op($op, \%opt); 1 };
    unless ($ok) {
        my $err = $@ || 'unknown error';
        chomp $err;
        warn "ERROR: $err\n";
        $errors++;
        last if $opt{strict};
    }
}

exit($errors ? 1 : 0);

# ================== PARSER ==================

sub parse_v4a_patch {
    my ($lines) = @_;
    my @ops;
    my $i = 0;
    my $n = scalar @$lines;

    while ($i < $n && $lines->[$i] !~ /^\*\*\* Begin Patch\b/) { $i++ }
    die "patch does not contain '*** Begin Patch'\n" if $i >= $n;
    $i++;

    while ($i < $n) {
        my $line = $lines->[$i];

        if ($line =~ /^\*\*\* End Patch\b/) { last }

        elsif ($line =~ /^\*\*\* Update File:\s*(.+?)\s*$/) {
            my $path = $1;
            $i++;
            my @hunks;
            my $cur;

            while ($i < $n) {
                my $l = $lines->[$i];
                last if $l =~ /^\*\*\* (?:Update|Add|Delete) File:/;
                last if $l =~ /^\*\*\* End Patch\b/;

                if ($l =~ /^\@\@\s*(.*?)\s*$/) {
                    push @hunks, $cur if defined $cur;
                    $cur = { hint => $1, changes => [] };
                    $i++;
                    next;
                }

                if (!defined $cur && $l =~ /^[ +\-]/) {
                    $cur = { hint => '', changes => [] };  # implicit hunk
                }

                push @{ $cur->{changes} }, $l if defined $cur;
                $i++;
            }
            push @hunks, $cur if defined $cur;
            push @ops, { type => 'update', path => $path, hunks => \@hunks };
        }

        elsif ($line =~ /^\*\*\* Add File:\s*(.+?)\s*$/) {
            my $path = $1;
            $i++;
            my $content = '';

            while ($i < $n) {
                my $l = $lines->[$i];
                last if $l =~ /^\*\*\* (?:Update|Add|Delete) File:/;
                last if $l =~ /^\*\*\* End Patch\b/;
                if ($l =~ /^\*\*\* End of File\b/) { $i++; next }

                if    ($l =~ /^\+(.*)$/) { $content .= "$1\n" }
                elsif ($l =~ /^\s*$/)    { }              # ignore blank seps
                else                     { die "unexpected line in Add File '$path': " . _escape($l) . "\n" }
                $i++;
            }
            push @ops, { type => 'add', path => $path, content => $content };
        }

        elsif ($line =~ /^\*\*\* Delete File:\s*(.+?)\s*$/) {
            push @ops, { type => 'delete', path => $1 };
            $i++;
        }

        else { $i++ }
    }

    return @ops;
}

# ================== APPLICATORS ==================

sub apply_v4a_op {
    my ($op, $o) = @_;
    if    ($op->{type} eq 'add')    { return apply_add($op, $o) }
    elsif ($op->{type} eq 'delete') { return apply_delete($op, $o) }
    elsif ($op->{type} eq 'update') { return apply_update($op, $o) }
    die "unknown op type '$op->{type}'\n";
}

sub apply_add {
    my ($op, $o) = @_;
    my $path = $op->{path};

    die "Add File: '$path' already exists\n" if -e $path;

    if ($o->{dry_run}) {
        print "DRY-RUN: would add $path (" . length($op->{content}) . " bytes)\n";
        return 1;
    }

    my $dir = dirname($path);
    if ($dir ne '' && $dir ne '.' && !-d $dir) {
        make_path($dir) or die "cannot create directory '$dir': $!\n";
    }

    open(my $fh, '>', $path) or die "cannot create '$path': $!\n";
    print $fh $op->{content};
    close $fh;

    if ($o->{diff}) {
        my $diff_file = write_diff_file($path, '', $op->{content}, 1);
        print "diff: $diff_file\n" if defined $diff_file;
    }

    print "added: $path\n";
    return 1;
}

sub apply_delete {
    my ($op, $o) = @_;
    my $path = $op->{path};

    die "Delete File: '$path' does not exist\n" unless -e $path;

    if ($o->{dry_run}) {
        print "DRY-RUN: would delete $path\n";
        return 1;
    }

    if ($o->{backup}) {
        my $bak = backup_path($path);
        copy($path, $bak) or die "backup failed for '$path': $!\n";
        print "backup: $bak\n";
    }

    unlink($path) or die "cannot delete '$path': $!\n";
    print "deleted: $path\n";
    return 1;
}

sub apply_update {
    my ($op, $o) = @_;
    my $path = $op->{path};

    open(my $fh, '<', $path) or die "cannot open '$path': $!\n";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $had_crlf = ($content =~ /\r\n/) ? 1 : 0;
    $content =~ s/\r\n/\n/g;

    my @lines = $content =~ /([^\n]*\n|[^\n]+$)/g;

    my $cursor = 0;

    for my $hunk (@{ $op->{hunks} }) {
        my (@before, @after);

        for my $l (@{ $hunk->{changes} }) {
            next if $l =~ /^\*\*\* End of File\b/;

            my $first = substr($l, 0, 1);
            my $rest  = substr($l, 1);

            if    ($first eq ' ') { push @before, $rest; push @after, $rest }
            elsif ($first eq '-') { push @before, $rest }
            elsif ($first eq '+') { push @after,  $rest }
            else {
                if ($l eq "\n" || $l eq '') {
                    push @before, "\n";
                    push @after,  "\n";
                } else {
                    die "invalid hunk line (no +/-/space prefix): " . _escape($l) . "\n";
                }
            }
        }

        my $found = _find_lines(\@lines, \@before, $cursor, $o->{ellipsis});

        # If an @@ hint exists, use it as an anchor.
        if ($found < 0 && defined $hunk->{hint} && length $hunk->{hint}) {
            my $hint = $hunk->{hint};

            for (my $k = $cursor; $k < @lines; $k++) {
                next unless index($lines[$k], $hint) >= 0;

                # The hunk may start on the hint line itself...
                $found = _find_lines(\@lines, \@before, $k, $o->{ellipsis});

                # ...or shortly after it.
                if ($found < 0) {
                    $found = _find_lines(\@lines, \@before, $k + 1, $o->{ellipsis});
                }

                last if $found >= 0;
            }
        }

        if ($found < 0) {
            my $h = defined $hunk->{hint} ? $hunk->{hint} : '(none)';
            die "hunk not found in '$path' (hint: $h)\n";
        }

        splice @lines, $found, scalar(@before), @after;
        $cursor = $found + scalar(@after);
    }

    my $new = join('', @lines);
    $new =~ s/\n/\r\n/g if $had_crlf;

    if ($o->{dry_run}) {
        print "DRY-RUN: would update $path\n";
        return 1;
    }

    if ($o->{backup}) {
        my $bak = backup_path($path);
        copy($path, $bak) or die "backup failed for '$path': $!\n";
        print "backup: $bak\n";
    }

    open(my $out, '>', $path) or die "cannot write '$path': $!\n";
    print $out $new;
    close $out;

    if ($o->{diff}) {
        my $diff_file = write_diff_file($path, $content, $new, 0);
        print "diff: $diff_file\n" if defined $diff_file;
    }

    print "patched: $path\n";
    return 1;
}

# ================== DIFF WRITER ==================

sub write_diff_file {
    my ($path, $old, $new, $is_new_file) = @_;
    my $diff_file = "$path.diff";

    my ($old_fh, $old_tmp) = tempfile(UNLINK => 1);
    my ($new_fh, $new_tmp) = tempfile(UNLINK => 1);
    print $old_fh $old; close $old_fh;
    print $new_fh $new; close $new_fh;

    my $old_label = $is_new_file ? File::Spec->devnull : $old_tmp;

    open(my $dfh, '-|', 'diff', '-u', $old_label, $new_tmp)
        or do {
            warn "cannot run diff: $!\n";
            return undef;
        };

    local $/;
    my $output = <$dfh>;
    close $dfh;
    my $status = $? >> 8;

    if ($status >= 2) {
        warn "diff failed with status $status\n";
        return undef;
    }

    my $stamp = strftime("%Y-%m-%d %H:%M:%S", localtime);

    $output =~ s{^---\s+\Q$old_label\E(?:\t.*)?$}{--- a/$path\t$stamp}m
        if !$is_new_file;
    $output =~ s{^---\s+\Q$old_label\E(?:\t.*)?$}{--- /dev/null\t$stamp}m
        if $is_new_file;
    $output =~ s{^\+\+\+\s+\Q$new_tmp\E(?:\t.*)?$}{+++ b/$path\t$stamp}m;

    open(my $ofh, '>', $diff_file) or do {
        warn "cannot write '$diff_file': $!\n";
        return undef;
    };
    print $ofh $output;
    close $ofh;

    return $diff_file;
}

# ================== HELPERS ==================

sub _find_lines {
    my ($file_lines, $pattern, $start, $allow_ellipsis) = @_;
    my $N = scalar @$pattern;
    my $M = scalar @$file_lines;
    return -1 if $N == 0 && $M == 0;
    return $start if $N == 0 && $start <= $M;
    return -1 if $start > $M;

    if ($allow_ellipsis && grep { /^\s*\.\.\.\s*$/ } @$pattern) {
        return _find_lines_ellipsis($file_lines, $pattern, $start);
    }

    return -1 if $start + $N > $M;

    for (my $i = $start; $i <= $M - $N; $i++) {
        my $ok = 1;
        for (my $j = 0; $j < $N; $j++) {
            if ($file_lines->[$i + $j] ne $pattern->[$j]) { $ok = 0; last }
        }
        return $i if $ok;
    }
    return -1;
}

sub _find_lines_ellipsis {
    my ($file_lines, $pattern, $start) = @_;
    my $M = scalar @$file_lines;
    return -1 if $start >= $M;

    my $regex = '';
    for my $line (@$pattern) {
        if ($line =~ /^\s*\.\.\.\s*$/) {
            $regex .= "(?:.*\n)*?";
        } else {
            $regex .= quotemeta($line);
        }
    }

    for my $i ($start .. $M - 1) {
        my $slice = join('', @$file_lines[$i .. $#$file_lines]);
        if ($slice =~ /^$regex/s) {
            return $i;
        }
    }

    return -1;
}

sub backup_path {
    my $path = shift;
    my $stamp = strftime("%Y%m%d-%H%M%S", localtime);
    my $bak = "$path.bak.$stamp";
    my $n = 1;
    while (-e $bak) { $bak = "$path.bak.$stamp.$n"; $n++ }
    return $bak;
}

sub _escape {
    my $s = shift;
    $s =~ s/\\/\\\\/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\r/\\r/g;
    $s =~ s/\t/\\t/g;
    return $s;
}

sub print_usage {
    print <<"USAGE";
Usage: $0 [options] <patch-file>

Applies a V4A-format patch to the files referenced inside it, and writes
a unified diff next to each modified file as <file>.diff.

Options:
  -n, --dry-run   Show what would happen without writing anything
  -b, --backup    Create a ".bak.<timestamp>" next to each modified file
      --diff      Write <file>.diff after patching (default: on)
      --no-diff   Do not write a .diff file
      --ellipsis  Allow '...' lines in context to act as non-greedy wildcards
      --strict    Stop at the first error (default: continue past errors)
  -h, --help      Show this message
USAGE
}
