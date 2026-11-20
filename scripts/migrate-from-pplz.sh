#!/bin/sh
# Moves the data of pplz, the old name of cardXchange, to the new folder. Run it one time, on the Mac.
#   scripts/migrate-from-pplz.sh [old folder] [new folder]
# Defaults: ~/Library/Application Support/pplz and ~/Library/Application Support/cardxchange.
# The script copies every record into a new store and checks the counts. Then it renames the old folder to
# pplz.migrated-<date>; that folder is the backup.
# See docs/changes/01_rename_to_cardxchange/02-data-migration.md §2.3.
set -eu

SUPPORT="$HOME/Library/Application Support"
OLD="${1:-$SUPPORT/pplz}"
NEW="${2:-$SUPPORT/cardxchange}"

fail() { echo "migrate-from-pplz: $*" >&2; exit 1; }

[ -f "$OLD/pplz.store" ] || fail "no store in $OLD"

# 1. never over a store that is there
[ -e "$NEW/cardxchange.store" ] && fail "$NEW/cardxchange.store exists already. Nothing was changed."
[ -e "$NEW/.cardxchange_SUPPORT" ] && fail "$NEW/.cardxchange_SUPPORT exists already. Nothing was changed."

# 2. nothing may write to the store while it is copied
for name in pplz cx cardXchange; do
    pgrep -x "$name" >/dev/null && fail "a process \"$name\" runs. Quit it first. Nothing was changed."
done

# 3. only the items that the migration knows
for item in "$OLD"/* "$OLD"/.[!.]*; do
    [ -e "$item" ] || continue
    case "$(basename "$item")" in
    pplz.store | pplz.store-wal | pplz.store-shm | .pplz_SUPPORT | pplz_ckAssets | contact-writes.jsonl | \
    geocache.json | geocache.json.lock | geocache.json.broken | backup-*) ;;
    *) fail "unknown item in $OLD: $(basename "$item"). Nothing was changed." ;;
    esac
done

# 4. copy the old store into a temporary folder, with its old name, so that Core Data finds .pplz_SUPPORT next to it;
#    the old folder is not written to
command -v cx >/dev/null || fail "no cx on the PATH. Build it (swift build -c release) and link it first. Nothing was changed."
TMP="$(mktemp -d)"
for suffix in "" -wal -shm; do
    [ -f "$OLD/pplz.store$suffix" ] && cp -p "$OLD/pplz.store$suffix" "$TMP/pplz.store$suffix"
done
[ -d "$OLD/.pplz_SUPPORT" ] && cp -Rp "$OLD/.pplz_SUPPORT" "$TMP/.pplz_SUPPORT"
mkdir -p "$NEW"
[ -f "$OLD/contact-writes.jsonl" ] && cp -p "$OLD/contact-writes.jsonl" "$NEW/contact-writes.jsonl"
[ -f "$OLD/geocache.json" ] && cp -p "$OLD/geocache.json" "$NEW/geocache.json"

undo() {
    rm -rf "$TMP" "$NEW/cardxchange.store" "$NEW/cardxchange.store-wal" "$NEW/cardxchange.store-shm" "$NEW/.cardxchange_SUPPORT" \
        "$NEW/contact-writes.jsonl"
}

# the counts of the old store, read before anything opens the temporary copy
counts() {
    sqlite3 -readonly "$1" "SELECT (SELECT COUNT(*) FROM ZPERSON), (SELECT COUNT(*) FROM ZEVENT), (SELECT COUNT(*) FROM ZTAG),
        (SELECT COUNT(*) FROM ZCONNECTION), (SELECT COUNT(*) FROM ZPERSONPHOTO), (SELECT COUNT(*) FROM ZFOLLOWUP),
        (SELECT COUNT(*) FROM ZSETTING), (SELECT COUNT(*) FROM ZLOCATEDADDRESS), (SELECT COUNT(*) FROM Z_2PARTICIPANTS),
        (SELECT COUNT(*) FROM Z_2TAGS), (SELECT COUNT(*) FROM Z_5TAGS);"
}
LABELS="persons|events|tags|connections|photos|follow-ups|settings|addresses|participants|event tags|person tags"
before="$(counts "$TMP/pplz.store")" || { undo; fail "could not read the copy of $OLD/pplz.store. Nothing was copied."; }

# 5. copy every record into a new store: a store that synced with the old iCloud container cannot sync with the new one
cx copy-store "$TMP/pplz.store" "$NEW/cardxchange.store" || { undo; fail "the copy failed. The new store was deleted."; }
sqlite3 "$NEW/cardxchange.store" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null || { undo; fail "could not checkpoint the new store. It was deleted."; }

# 6. the same counts in both stores, the links between records included
after="$(counts "$NEW/cardxchange.store")" || { undo; fail "could not read the new store. It was deleted."; }
if [ "$before" != "$after" ]; then
    undo
    fail "the counts are different ($LABELS: old $before, new $after). The new store was deleted."
fi
rm -rf "$TMP"
echo "$LABELS: $after"

# 7. the old folder becomes the backup; an old build finds no store there
BACKUP="$(dirname "$OLD")/pplz.migrated-$(date +%Y-%m-%d)"
[ -e "$BACKUP" ] && fail "$BACKUP exists. The copy is complete; rename $OLD by hand."
mv "$OLD" "$BACKUP"
echo "Migrated to $NEW. The old folder is now $BACKUP."
