#!/usr/bin/env bash
# Builds evidence/REPORT.md: every automatic check with its latest result, plus an
# index of the evidence files. Paste parts of it into the Phase 2 final report.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
R="$EVID/results.tsv"; OUT="$EVID/REPORT.md"
{
  echo "# Evidence report – $TEAM  ($(date '+%F %T'))"; echo
  echo "## Automatic checks (latest result of each)"; echo
  if [ -f "$R" ]; then
    echo "| Scene | Check | Result | When |"; echo "|---|---|---|---|"
    tail -n +2 "$R" | awk -F'\t' '{k=$2 FS $3; last[k]=$0; if(!(k in seen)){seen[k]=1; order[++n]=k}}
      END{for(i=1;i<=n;i++){split(last[order[i]],f,FS); printf "| %s | %s | %s | %s |\n", f[2], f[3], (f[4]=="PASS"?"✅ PASS":"❌ FAIL"), f[1]}}'
    echo; echo "Totals over all runs: $(tail -n +2 "$R" | grep -c 'PASS$' || true) passed, $(tail -n +2 "$R" | grep -c 'FAIL$' || true) failed."
  else echo "_No live run yet – run \`make live\`._"; fi
  echo; echo "## Evidence files"; echo
  [ -f "$EVID/inventory.md" ] && echo "- IP / MAC / gateway inventory: \`evidence/inventory.md\`"
  ls "$EVID"/pcap/*.pcap >/dev/null 2>&1 && for f in "$EVID"/pcap/*.pcap; do echo "- Packet capture: \`${f#"$ROOT"/}\`"; done
  if [ -d "$EVID/live" ]; then
    for d in "$EVID"/live/*/; do
      echo "- Live run \`${d#"$ROOT"/}\`: $(ls "$d" | grep -c . ) scenes (each: one file per terminal + control)"
    done
  fi
  [ -d "$EVID/terminal-logs" ] && echo "- Raw timestamped terminal recordings: \`evidence/terminal-logs/\`"
} > "$OUT"
echo "wrote ${OUT#"$ROOT"/}"
