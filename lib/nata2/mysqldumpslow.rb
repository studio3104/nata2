require 'nata2'

module Nata2::Mysqldumpslow
  def self.dump(slow_queries, sort_order = 'c')
    summation = {}
    slow_queries.each do |slow_query|
      sql = slow_query[:sql]
      next unless sql
      normarized_sql = normalize(sql)
      summation = sum(summation, normarized_sql, slow_query)
    end

    summarized = summarize(summation)
    sort_summarized(summarized, sort_order)
  end

  private

  def self.normalize(sql)
    sql = sql.gsub(/\b\d+\b/, 'N')
    sql = sql.gsub(/\b0x[0-9A-Fa-f]+\b/, 'N')
    sql = sql.gsub(/''/, %q{'S'})
    sql = sql.gsub(/''/, %q{'S'})
    sql = sql.gsub(/(\\')/, '')
    sql = sql.gsub(/(\\')/, '')
    sql = sql.gsub(/'[^']+'/, %q{'S'})
    sql = sql.gsub(/'[^']+'/, %q{'S'})
    # abbreviate massive "in (...)" statements and similar
    # s!(([NS],){100,})!sprintf("$2,{repeated %d times}",length($1)/2)!eg;
    sql
  end

  def self.sum(summation, normarized_sql, slow_query)
    summation[normarized_sql] ||= {
      count: 0, user: [slow_query[:user]], host: [slow_query[:host]],
      query_time: 0.0, lock_time: 0.0,
      rows_sent: 0, rows_examined: 0,
      raw_sql: slow_query[:sql]
    }

    summation[normarized_sql][:count] += 1
    summation[normarized_sql][:user] << slow_query[:user]
    summation[normarized_sql][:host] << slow_query[:host]
    summation[normarized_sql][:query_time] += slow_query[:query_time]
    summation[normarized_sql][:lock_time] += slow_query[:lock_time]
    summation[normarized_sql][:rows_sent] += slow_query[:rows_sent]
    summation[normarized_sql][:rows_examined] += slow_query[:rows_examined]

    summation
  end

  def self.summarize(summation)
    summation.map do |normarized_sql, c|
      count = c[:count].to_f
      {
        count: count.to_i, user: c[:user].uniq, host: c[:host].uniq,
        average: {
          query_time: c[:query_time]/count, lock_time: c[:lock_time]/count,
          rows_sent: c[:rows_sent]/count, rows_examined: c[:rows_examined]/count
        },
        summation: {
          query_time: c[:query_time], lock_time: c[:lock_time],
          rows_sent: c[:rows_sent], rows_examined: c[:rows_examined]
        },
        normarized_sql: normarized_sql,
        raw_sql: c[:row_sql]
      }
    end
  end

  def self.sort_summarized(summarized, order)
    result = case order
             when 'at'
               summarized.sort_by { |query| query[:average][:query_time] }
             when 'al'
               summarized.sort_by { |query| query[:average][:lock_time] }
             when 'ar'
               summarized.sort_by { |query| query[:average][:rows_sent] }
             when 'c'
               summarized.sort_by { |query| query[:count] }
             when 't'
               summarized.sort_by { |query| query[:summation][:query_time] }
             when 'l'
               summarized.sort_by { |query| query[:summation][:lock_time] }
             when 'r'
               summarized.sort_by { |query| query[:summation][:rows_sent] }
             else
               raise ArgumentError, %q{sort order is either of 'at', 'al', 'ar', 't', 'l', 'r' or 'c'.}
             end

    result.reverse
  end
end

__END__
# Copyright (c) 2000, 2011, Oracle and/or its affiliates. All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public
# License as published by the Free Software Foundation; version 2
# of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Library General Public License for more details.
#
# You should have received a copy of the GNU Library General Public
# License along with this library; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA

# mysqldumpslow - parse and summarize the MySQL slow query log

# Original version by Tim Bunce, sometime in 2000.
# Further changes by Tim Bunce, 8th March 2001.
# Handling of strings with \ and double '' by Monty 11 Aug 2001.

use strict;
use Getopt::Long;

# t=time, l=lock time, r=rows
# at, al, and ar are the corresponding averages

my %opt = (
    s => 'at',
    h => '*',
);

GetOptions(\%opt,
    'v|verbose+',# verbose
    'help+',	# write usage info
    'd|debug+',	# debug
    's=s',	# what to sort by (al, at, ar, c, t, l, r)
    'r!',	# reverse the sort order (largest last instead of first)
    't=i',	# just show the top n queries
    'a!',	# don't abstract all numbers to N and strings to 'S'
    'n=i',	# abstract numbers with at least n digits within names
    'g=s',	# grep: only consider stmts that include this string
    'h=s',	# hostname of db server for *-slow.log filename (can be wildcard)
    'i=s',	# name of server instance (if using mysql.server startup script)
    'l!',	# don't subtract lock time from total time
) or usage("bad option");

$opt{'help'} and usage();

unless (@ARGV) {
    my $defaults   = `my_print_defaults mysqld`;
    my $basedir = ($defaults =~ m/--basedir=(.*)/)[0]
	or die "Can't determine basedir from 'my_print_defaults mysqld' output: $defaults";
    warn "basedir=$basedir\n" if $opt{v};

    my $datadir = ($defaults =~ m/--datadir=(.*)/)[0];
    my $slowlog = ($defaults =~ m/--slow-query-log-file=(.*)/)[0];
    if (!$datadir or $opt{i}) {
	# determine the datadir from the instances section of /etc/my.cnf, if any
	my $instances  = `my_print_defaults instances`;
	die "Can't determine datadir from 'my_print_defaults mysqld' output: $defaults"
	    unless $instances;
	my @instances = ($instances =~ m/^--(\w+)-/mg);
	die "No -i 'instance_name' specified to select among known instances: @instances.\n"
	    unless $opt{i};
	die "Instance '$opt{i}' is unknown (known instances: @instances)\n"
	    unless grep { $_ eq $opt{i} } @instances;
	$datadir = ($instances =~ m/--$opt{i}-datadir=(.*)/)[0]
	    or die "Can't determine --$opt{i}-datadir from 'my_print_defaults instances' output: $instances";
	warn "datadir=$datadir\n" if $opt{v};
    }

    if ( -f $slowlog ) {
        @ARGV = ($slowlog);
        die "Can't find '$slowlog'\n" unless @ARGV;
    } else {
        @ARGV = <$datadir/$opt{h}-slow.log>;
        die "Can't find '$datadir/$opt{h}-slow.log'\n" unless @ARGV;
    }
}

warn "\nReading mysql slow query log from @ARGV\n";

my @pending;
my %stmt;
$/ = ";\n#";		# read entire statements using paragraph mode
while ( defined($_ = shift @pending) or defined($_ = <>) ) {
    warn "[[$_]]\n" if $opt{d};	# show raw paragraph being read

    my @chunks = split /^\/.*Version.*started with[\000-\377]*?Time.*Id.*Command.*Argument.*\n/m;
    if (@chunks > 1) {
	unshift @pending, map { length($_) ? $_ : () } @chunks;
	warn "<<".join(">>\n<<",@chunks).">>" if $opt{d};
	next;
    }

    s/^#? Time: \d{6}\s+\d+:\d+:\d+.*\n//;
    my ($user,$host,$dummy,$thread_id) = s/^#? User\@Host:\s+(\S+)\s+\@\s+(\S+)\s+\S+(\s+Id:\s+(\d+))?.*\n// ? ($1,$2,$3,$4) : ('','','','','');

    s/^# Query_time: ([0-9.]+)\s+Lock_time: ([0-9.]+)\s+Rows_sent: ([0-9.]+).*\n//;
    my ($t, $l, $r) = ($1, $2, $3);
    $t -= $l unless $opt{l};

    # remove fluff that mysqld writes to log when it (re)starts:
    s!^/.*Version.*started with:.*\n!!mg;
    s!^Tcp port: \d+  Unix socket: \S+\n!!mg;
    s!^Time.*Id.*Command.*Argument.*\n!!mg;

    s/^use \w+;\n//;	# not consistently added
    s/^SET timestamp=\d+;\n//;

    s/^[ 	]*\n//mg;	# delete blank lines
    s/^[ 	]*/  /mg;	# normalize leading whitespace
    s/\s*;\s*(#\s*)?$//;	# remove trailing semicolon(+newline-hash)

    next if $opt{g} and !m/$opt{g}/io;

    unless ($opt{a}) {
	s/\b\d+\b/N/g;
	s/\b0x[0-9A-Fa-f]+\b/N/g;
        s/''/'S'/g;
        s/""/"S"/g;
        s/(\\')//g;
        s/(\\")//g;
        s/'[^']+'/'S'/g;
        s/"[^"]+"/"S"/g;
	# -n=8: turn log_20001231 into log_NNNNNNNN
	s/([a-z_]+)(\d{$opt{n},})/$1.('N' x length($2))/ieg if $opt{n};
	# abbreviate massive "in (...)" statements and similar
	s!(([NS],){100,})!sprintf("$2,{repeated %d times}",length($1)/2)!eg;
    }

    my $s = $stmt{$_} ||= { users=>{}, hosts=>{} };
    $s->{c} += 1;
    $s->{t} += $t;
    $s->{l} += $l;
    $s->{r} += $r;
    $s->{users}->{$user}++ if $user;
    $s->{hosts}->{$host}++ if $host;

    warn "{{$_}}\n\n" if $opt{d};	# show processed statement string
}

foreach (keys %stmt) {
    my $v = $stmt{$_} || die;
    my ($c, $t, $l, $r) = @{ $v }{qw(c t l r)};
    $v->{at} = $t / $c;
    $v->{al} = $l / $c;
    $v->{ar} = $r / $c;
}

my @sorted = sort { $stmt{$b}->{$opt{s}} <=> $stmt{$a}->{$opt{s}} } keys %stmt;
@sorted = @sorted[0 .. $opt{t}-1] if $opt{t};
@sorted = reverse @sorted         if $opt{r};

foreach (@sorted) {
    my $v = $stmt{$_} || die;
    my ($c, $t,$at, $l,$al, $r,$ar) = @{ $v }{qw(c t at l al r ar)};
    my @users = keys %{$v->{users}};
    my $user  = (@users==1) ? $users[0] : sprintf "%dusers",scalar @users;
    my @hosts = keys %{$v->{hosts}};
    my $host  = (@hosts==1) ? $hosts[0] : sprintf "%dhosts",scalar @hosts;
    printf "Count: %d  Time=%.2fs (%ds)  Lock=%.2fs (%ds)  Rows=%.1f (%d), $user\@$host\n%s\n\n",
	    $c, $at,$t, $al,$l, $ar,$r, $_;
}

sub usage {
    my $str= shift;
    my $text= <<HERE;
Usage: mysqldumpslow [ OPTS... ] [ LOGS... ]

Parse and summarize the MySQL slow query log. Options are

  --verbose    verbose
  --debug      debug
  --help       write this text to standard output

  -v           verbose
  -d           debug
  -s ORDER     what to sort by (al, at, ar, c, l, r, t), 'at' is default
                al: average lock time
                ar: average rows sent
                at: average query time
                 c: count
                 l: lock time
                 r: rows sent
                 t: query time  
  -r           reverse the sort order (largest last instead of first)
  -t NUM       just show the top n queries
  -a           don't abstract all numbers to N and strings to 'S'
  -n NUM       abstract numbers with at least n digits within names
  -g PATTERN   grep: only consider stmts that include this string
  -h HOSTNAME  hostname of db server for *-slow.log filename (can be wildcard),
               default is '*', i.e. match all
  -i NAME      name of server instance (if using mysql.server startup script)
  -l           don't subtract lock time from total time

HERE
    if ($str) {
      print STDERR "ERROR: $str\n\n";
      print STDERR $text;
      exit 1;
    } else {
      print $text;
      exit 0;
    }
}
