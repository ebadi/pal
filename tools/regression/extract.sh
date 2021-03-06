#!/bin/bash
set -e

DB="pal.db"

usage() {
    echo Usage: $0 PLATFORM >&2
    echo >&2
    echo Create HTML report for PLATFORM >&2
    echo Example: $0 x86_64 >&2
    exit 1
}

[ $# == 1 ] || usage
platform=$1

if ! which sqlite3 >/dev/null; then
    echo This tool needs sqlite3 >&2
    exit 1
fi

if ! which gawk >/dev/null; then
    echo This tool needs gawk >&2
    exit 1
fi

if ! [ -e ${DB} ]; then
    echo Database \'${DB}\' not found >&2
    exit 1
fi

head=$(git rev-parse HEAD)
files_qry="SELECT DISTINCT file FROM report WHERE commit_sha=\"${head}\" ORDER BY file ASC;"
files=$(echo "$files_qry" | sqlite3 ${DB});

cat << EOF
<html>
<head>
<title>PAL code size report for ${platform}</title>
<style>
.increase {
    background-color: red;
}
.decrease {
    background-color: green;
}

table {
    border-collapse: collapse;
    border: 1px solid #222;
}
th {
    border-bottom: 1px solid #222;
}
tr.newsymbol {
    border-top: 1px solid #222;
}
td, th {
    border-left: 1px solid #222;
    border-right: 1px solid #222;
    padding-left: 1em;
    padding-right: 1em;
}
.commit, .commit a, .symbol {
    font-family: "Courier New", Courier, monospace;
}
.commit, .commit a {
    min-width: 64ch;
}
.symbol {
    min-width: 24ch;
}
.number {
    text-align: right;
    min-width: 6ch;
}
</style>
</head>
<body>
<h1>PAL code size report for ${platform}</h1>
<p>Latest commit: ${head}</p>
EOF

for f in $files; do
    f_src=$(echo $f | sed 's/\.o$/\.c/g')
    echo "<h2><a href=\"https://github.com/parallella/pal/tree/master/${f_src}\">${f_src}</a></h2>"
    echo "<table>"
    echo "<tr><th>Symbol</th><th>Date (GMT+0)</th><th>Commit</th><th>Size</th></tr>"
    qry="SELECT datetime(commit_date, 'unixepoch'), commit_sha, symbol, size FROM report WHERE file='${f}' AND platform='${platform}' GROUP BY symbol, commit_date;"
    (echo .mode csv && echo $qry) | sqlite3 ${DB} | gawk -F"," '
    BEGIN {
        prev_size=(-1);
        prev_symbol="";
        cmd="git rev-parse --abbrev-ref HEAD";
        cmd | getline current_branch;
        close(cmd);
    }
    {
        date=$1;
        gsub(/"/, "", date); # Remove quotes around date
        sha=$2;
        abbrev_sha = substr(sha, 0, 12);
        symbol=$3;
        size=$4;

        # If no diff ignore
        if (size == prev_size && symbol == prev_symbol)
            next;

        # If commit is not in current branch continue.
        # ??? TODO: Not always what we want to do
        cmd=sprintf("git branch --contains %s | tr -d \" *\" | grep -q ^%s$", sha, current_branch);
        if (0 != system(cmd))
            next;

        # Highlight if increased or decreased
        if (prev_size == (-1) || prev_symbol != symbol || prev_size == size)
            size_str=sprintf("<td class=\"number\">%d</td>", size);
        else if (prev_size > size)
            size_str=sprintf("<td class=\"number decrease\">%d</td>", size);
        else
            size_str=sprintf("<td class=\"number increase\">%d</td>", size);

        if (symbol == prev_symbol)
            symbol_str="";
        else
            symbol_str=symbol;

        if (symbol != prev_symbol && prev_symbol != "")
            tr_str="<tr class=\"newsymbol\">";
        else
            tr_str="<tr>";

        cmd=sprintf("git show %s --format=\"%%s\"| head -n1\n", sha);
        cmd | getline oneline;
        close(cmd);

        if (length(oneline) > 50)
            oneline=sprintf("%s...", substr(oneline, 0, 47));

        commit_str=sprintf("<a href=\"https://github.com/parallella/pal/commit/%s\">%s: %s</a>",
                           sha, abbrev_sha, oneline);


        printf("%s<td class=\"symbol\">%s</td><td>%s</td><td class=\"commit\">%s</td>%s</tr>\n",
               tr_str, symbol_str, date, commit_str, size_str);

        prev_size=size;
        prev_symbol=symbol;
    } '
    echo "</table>"
done

cat << EOF
</body>
</html>
EOF

