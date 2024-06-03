#!/usr/bin/env perl
my $columns = 0;
my $has_header = 0;
while (<>) {
    if (m{<body>}) {
        $ready = 1;
        next;
    }
    next unless $ready;
    s!<h1>(.*)</h1>!# $1!;
    if (s{<table>}{\n}) {
        $table = 1;
        $has_header = 0;
        $columns = 0;
    }
    s{<a href=".*?">(.*?)</a>}{$1}g;
    if ($has_header==0 && m{<tr><td class="h"}) {
        print "|-|-|\n|-|-|\n";
        $has_header=1;
    }
    if (m{<td class="h" align="right">Thresholds:}) {
        print "|-|-|-|-|\n";
        print "|-|-|-|-|\n";
    }
    s{<(?:div|tr)>}{}g;
    if (m{</tr>} && $columns) {
        print ('|-'x $columns);
        print "|\n";
        $columns=0;
        $has_header=1;
    }
    ++$columns while (s{<th.*?>}{|});
    s{(<td[^>]*?class="c3"[^>]*>)}{$1💯}g;
    s{(<td[^>]*?class="c2"[^>]*>)}{$1✅}g;
    s{(<td[^>]*?class="c1"[^>]*>)}{$1⚠️}g;
    s{(<td[^>]*?class="c0"[^>]*>)}{$1❌}g;
    s{<td.*?>}{|}g;
    s{</t[dh]>\n}{};
    s{</\w+?>}{}g;
    s{<br/>}{\n}g;
    s{^ +}{}g;
    print;
}
