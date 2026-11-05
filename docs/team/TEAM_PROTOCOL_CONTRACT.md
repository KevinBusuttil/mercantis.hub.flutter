# Atlas Team: app and server compatibility (C6)

The app and the Team server are released separately. This contract decides
which pairs may talk, so an app never syncs with a server that lacks what it
relies on, and a server can retire an app that would be unsafe.

## The contract

The backend owns it: `contract/team_protocol.json` in
`neuradix-atlas-team-backend`. The hub keeps a copy in
`test/fixtures/team_protocol.json`. CI fails if the two differ, and unit
tests on both sides check the code constants against the file.

| Level | What it added |
|---|---|
| 1 | Mutation-log sync, identity and devices, server posting for sales, purchasing, stock, POS and payments |
| 2 | C4: history checkpoints, `sync/history`, `report-lost-history` |
| 3 | C5: server posting for Journal Entry, Expense and Customer Deposit; the books lock only through `set-books-lock`; `GET /protocol` and the `X-Atlas-Protocol` header |

This release: the app speaks **3** and needs a server at **3** or later.
The server speaks **3** and accepts apps from `ATLAS_MIN_CLIENT_PROTOCOL`
(default 0, which includes apps built before the contract).

## How it is enforced

- **App to server.** Every Team request carries `X-Atlas-Protocol: 3`
  (`lib/team/team_protocol.dart`, wrapped into every Team HTTP client).
- **Before each sync** the app reads `GET /protocol`. A server below 3, or
  one with no `/protocol` at all, stops the sync with: "This Team server is
  older than this version of Atlas needs… Ask whoever runs the server to
  update it". Nothing is sent and nothing on the device changes. A server
  whose minimum is above 3 stops it with "Update Atlas on this device".
  Submitting from a form syncs first, so it is covered too.
- **On the server** a request below the minimum gets 426 with the update
  message, before authentication or any handler runs. Health, readiness,
  webhooks, portal and pay pages are never refused.
- An unreachable server is a normal network failure, not a mismatch.

## Changing it

- Raise the level (backend constant, contract file, app constant) whenever
  the app starts to rely on something an older server does not do. Add a
  row above saying what.
- Release the server first, then the app.
- Raise the server's minimum only when an older app would be unsafe, and
  only after the devices have updated (`docs/OPERATIONS.md` in the backend).
- Re-pin `tool/team_backend.pin` to the backend commit the app needs. CI
  then runs the full Team E2E against it.

## Evidence

- Backend: `src/protocol.rs` unit tests (contract file, refusal rules,
  clamped minimum) and `tests/protocol.rs` (over HTTP with the minimum at 3:
  unversioned and level-2 apps get 426 even with a bad token, a non-numeric
  header is 400, levels 3 and 4 pass, health/ready/protocol are never
  refused).
- Hub: `test/team_protocol_test.dart` (header on all three Team clients,
  older server refused before any other request, newer-app-needed message,
  network failure) and `test/team_e2e/team_protocol_e2e_test.dart` against
  the pinned server.
- These are Linux container and CI runs. They are not device or pilot
  evidence.
