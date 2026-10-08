#!/usr/bin/env bash
# Fills the test server from start-server.sh with demo data, through the Deck API as Alice: three boards with
# lists, cards, labels, due dates, assignees, comments and an attachment, one board shared with Bob and the
# "family" group, and a board of Bob's own. The UI tests and the README screenshots use it. No personal data.
set -euo pipefail

E2E_DIR="${E2E_DIR:-build/e2e}"
# shellcheck source=/dev/null
. "$E2E_DIR/env"
DECK="$E2E_SERVER_URL/index.php/apps/deck/api/v1.0"
DECK_V11="$E2E_SERVER_URL/index.php/apps/deck/api/v1.1"
OCS="$E2E_SERVER_URL/ocs/v2.php/apps/deck/api/v1.0"

app_password() { # user password
    curl -fsS -u "$1:$2" -H 'OCS-APIRequest: true' "$E2E_SERVER_URL/ocs/v2.php/core/getapppassword?format=json" |
        jq -r .ocs.data.apppassword
}
ALICE_AUTH="alice:$(app_password alice "$E2E_ALICE_PASSWORD")"
BOB_AUTH="bob:$(app_password bob "$E2E_BOB_PASSWORD")"

# api AUTH METHOD URL [JSON]: prints the response body.
api() {
    curl -fsS -u "$1" -X "$2" -H 'OCS-APIRequest: true' -H 'Content-Type: application/json' \
        -H 'Accept: application/json' "$3" ${4:+--data "$4"}
}
as_alice() { api "$ALICE_AUTH" "$@"; }

# Dates relative to today, so "overdue" and "due soon" look the same whenever the screenshots are taken.
iso_date() { # days from now, e.g. 5 or -2
    if date -v+1d >/dev/null 2>&1; then
        # BSD date: -v5d would set the day of the month; -v+5d adds five days.
        case "$1" in -*) offset="$1" ;; *) offset="+$1" ;; esac
        date -u -v"${offset}d" +%Y-%m-%dT17:00:00+00:00
    else
        date -u -d "$1 days" +%Y-%m-%dT17:00:00+00:00
    fi
}

# Deck makes a welcome board for every new user; the demo boards replace it.
for auth in "$ALICE_AUTH" "$BOB_AUTH"; do
    for id in $(api "$auth" GET "$DECK/boards" | jq -r '.[] | select(.title | startswith("Welcome")) | .id'); do
        api "$auth" DELETE "$DECK/boards/$id" >/dev/null
    done
done

board() { as_alice POST "$DECK/boards" "$(jq -nc --arg t "$1" --arg c "$2" '{title: $t, color: $c}')" | jq -r .id; }
stack() { as_alice POST "$DECK/boards/$1/stacks" "$(jq -nc --arg t "$2" --argjson o "$3" '{title: $t, order: $o}')" | jq -r .id; }
label() { as_alice POST "$DECK/boards/$1/labels" "$(jq -nc --arg t "$2" --arg c "$3" '{title: $t, color: $c}')" | jq -r .id; }
# card BOARD STACK ORDER TITLE [DESCRIPTION] [DUE]
card() {
    as_alice POST "$DECK/boards/$1/stacks/$2/cards" "$(jq -nc --arg t "$4" --argjson o "$3" \
        --arg d "${5:-}" --arg due "${6:-}" \
        '{title: $t, type: "plain", order: $o, description: $d} + (if $due == "" then {} else {duedate: $due} end)')" |
        jq -r .id
}
tag() { as_alice PUT "$DECK/boards/$1/stacks/$2/cards/$3/assignLabel" "{\"labelId\": $4}" >/dev/null; }
assign() { as_alice PUT "$DECK/boards/$1/stacks/$2/cards/$3/assignUser" "{\"userId\": \"$4\"}" >/dev/null; }
share() { # board type participant edit
    as_alice POST "$DECK/boards/$1/acl" "$(jq -nc --argjson type "$2" --arg p "$3" --argjson e "$4" \
        '{type: $type, participant: $p, permissionEdit: $e, permissionShare: false, permissionManage: false}')" >/dev/null
}
comment() { # auth card message
    api "$1" POST "$OCS/cards/$2/comments" "$(jq -nc --arg m "$3" '{message: $m}')" >/dev/null
}
done_card() { # board stack card: marks it done (Deck 1.12+)
    local current
    current=$(as_alice GET "$DECK/boards/$1/stacks/$2/cards/$3")
    as_alice PUT "$DECK/boards/$1/stacks/$2/cards/$3" "$(echo "$current" |
        jq -c --arg now "$(iso_date -1)" '{title, type, order, description, duedate, owner: .owner.uid, done: $now}')" >/dev/null
}

echo "==> Seeding demo boards"

home=$(board "Home renovation" "2E8B57")
ideas=$(stack "$home" "Ideas" 0)
todo=$(stack "$home" "To do" 1)
doing=$(stack "$home" "In progress" 2)
finished=$(stack "$home" "Done" 3)
kitchen=$(label "$home" "Kitchen" "E9A23B")
garden=$(label "$home" "Garden" "4CAF50")
budget=$(label "$home" "Budget" "C0392B")
share "$home" 0 bob true
share "$home" 1 family false

c=$(card "$home" "$ideas" 0 "Herb garden on the balcony" "Basil, mint and rosemary in window boxes.")
tag "$home" "$ideas" "$c" "$garden"
card "$home" "$ideas" 1 "Reading nook under the stairs" >/dev/null

c=$(card "$home" "$todo" 0 "Choose paint colours" "$(printf '%s\n' \
    'Living room and hallway.' '' \
    '- [x] Collect sample cards' '- [x] Paint test patches' '- [ ] Decide on the hallway' '- [ ] Order paint')" \
    "$(iso_date 5)")
tag "$home" "$todo" "$c" "$kitchen"
assign "$home" "$todo" "$c" alice
assign "$home" "$todo" "$c" bob
comment "$BOB_AUTH" "$c" "The sage green looked great in daylight."
comment "$ALICE_AUTH" "$c" "Agreed. Let's order two tins on Friday."
paint_card=$c
c=$(card "$home" "$todo" 1 "Get quotes for new windows" "Three quotes, including fitting." "$(iso_date -2)")
tag "$home" "$todo" "$c" "$budget"
assign "$home" "$todo" "$c" bob
card "$home" "$todo" 2 "Fix the dripping tap" >/dev/null

c=$(card "$home" "$doing" 0 "Kitchen cabinets" "Sand, prime and paint the doors." "$(iso_date 12)")
tag "$home" "$doing" "$c" "$kitchen"
assign "$home" "$doing" "$c" alice
c=$(card "$home" "$doing" 1 "Plan the vegetable patch")
tag "$home" "$doing" "$c" "$garden"

c=$(card "$home" "$finished" 0 "Clear out the garage")
done_card "$home" "$finished" "$c"
c=$(card "$home" "$finished" 1 "Set a budget" "Spreadsheet shared with the family.")
tag "$home" "$finished" "$c" "$budget"
done_card "$home" "$finished" "$c"

# An attachment on the paint card.
attachment="$E2E_DIR/paint-colours.txt"
printf 'Sage green\nWarm white\nSlate grey\n' >"$attachment"
# Deck 1.17 and 1.18 require the "data" field, though it's unused for uploads.
curl -fsS -u "$ALICE_AUTH" -H 'OCS-APIRequest: true' -F type=file -F data= -F "file=@$attachment" \
    "$DECK_V11/boards/$home/stacks/$todo/cards/$paint_card/attachments" >/dev/null

launch=$(board "Product launch" "8E44AD")
backlog=$(stack "$launch" "Backlog" 0)
week=$(stack "$launch" "This week" 1)
stack "$launch" "Shipped" 2 >/dev/null
card "$launch" "$backlog" 0 "Write the release notes" >/dev/null
card "$launch" "$backlog" 1 "Record a short demo video" >/dev/null
card "$launch" "$week" 0 "Update the website" "" "$(iso_date 2)" >/dev/null

reading=$(board "Reading list" "D35400")
stack "$reading" "To read" 0 >/dev/null
stack "$reading" "Reading" 1 >/dev/null
stack "$reading" "Finished" 2 >/dev/null

# Bob's own board, so switching accounts shows something different.
bob_board=$(api "$BOB_AUTH" POST "$DECK/boards" '{"title": "Bob'"'"'s errands", "color": "16A085"}' | jq -r .id)
bob_stack=$(api "$BOB_AUTH" POST "$DECK/boards/$bob_board/stacks" '{"title": "Errands", "order": 0}' | jq -r .id)
api "$BOB_AUTH" POST "$DECK/boards/$bob_board/stacks/$bob_stack/cards" '{"title": "Post office", "type": "plain", "order": 0}' >/dev/null

# A big board on the realistic server (#142), as real boards grow: 12 lists of 25 cards, some with labels and
# due dates. The UI tests and screenshots don't use it.
if [ "${E2E_PROFILE:-minimal}" = realistic ]; then
    echo "==> Seeding the large board"
    big=$(board "Big backlog" "2C3E50")
    big_labels=("$(label "$big" "Bug" "C0392B")" "$(label "$big" "Feature" "2E8B57")" "$(label "$big" "Chore" "7F8C8D")")
    for list in $(seq 1 12); do
        s=$(stack "$big" "List $list" "$list")
        for n in $(seq 1 25); do
            if [ $((n % 4)) = 0 ]; then due=$(iso_date $((n - 10))); else due=""; fi
            c=$(card "$big" "$s" "$n" "Card $list.$n" "Card $n of list $list." "$due")
            if [ $((n % 3)) = 0 ]; then
                tag "$big" "$s" "$c" "${big_labels[$((n % 9 / 3))]}"
            fi
        done
    done
fi

# The seed's own app passwords are no longer needed.
for auth in "$ALICE_AUTH" "$BOB_AUTH"; do
    curl -fsS -u "$auth" -X DELETE -H 'OCS-APIRequest: true' "$E2E_SERVER_URL/ocs/v2.php/core/apppassword" >/dev/null
done
echo "==> Seeded: Home renovation ($home), Product launch ($launch), Reading list ($reading), Bob's errands ($bob_board)${big:+, Big backlog ($big)}"
