#!/bin/sh
# Copies the rime-ice snapshot to $1 and applies Rime/hal/demoted.tsv to cn_dicts/base (PLAN.md D29).
# Every demoted entry drops just below the lowest other entry of its code; a demotion that
# matches nothing fails the build, so the list cannot rot silently across snapshot updates.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
dest=${1:?usage: stage-rime-data.sh <RimeData dir>}
base=cn_dicts/base.dict.yaml

mkdir -p "$dest"
rsync -a --delete --exclude "/$base" "$root/Rime/rime-ice/" "$dest/"

staged=$(mktemp "$dest/cn_dicts/.base.XXXXXX")
trap 'rm -f "$staged"' EXIT
LC_ALL=C awk -F '\t' -v OFS='\t' '
    FILENAME == ARGV[1] {
        if ($0 !~ /^#/ && NF == 2) { demoted[$1 FS $2] = 1; unmatched[$1 FS $2] = 1; codes[$2] = 1 }
        next
    }
    FNR == 1 { pass++; body = 0 }
    !body {
        if (pass == 2 && FNR == 1)
            print "# Modified by HAL (https://github.com/YaphetSf/HAL): scripts/stage-rime-data.sh lowers the weights of the entries in Rime/hal/demoted.tsv"
        if ($0 == "...") body = 1
        if (pass == 2) print
        next
    }
    pass == 1 {
        if ($0 ~ /^#/ || NF < 3) next
        if (($1 FS $2) in demoted) { delete unmatched[$1 FS $2]; next }
        if (($2 in codes) && (!($2 in lowest) || $3 + 0 < lowest[$2])) lowest[$2] = $3 + 0
        next
    }
    {
        if ($0 !~ /^#/ && NF >= 3 && ($1 FS $2) in demoted)
            $3 = ($2 in lowest) && lowest[$2] > 1 ? lowest[$2] - 1 : 0
        print
    }
    END {
        for (key in unmatched) { print "stage-rime-data: no entry for demotion " key > "/dev/stderr"; failed = 1 }
        exit failed
    }
' "$root/Rime/hal/demoted.tsv" "$root/Rime/rime-ice/$base" "$root/Rime/rime-ice/$base" > "$staged"

if cmp -s "$staged" "$dest/$base"; then
    rm "$staged"
else
    chmod 644 "$staged"
    mv "$staged" "$dest/$base"
fi
