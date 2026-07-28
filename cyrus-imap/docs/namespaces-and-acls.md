# IMAP namespaces & ACLs

Conceptual reference for how mailboxes are organized and secured in this
deployment. For `cyradm` command syntax, see `docs/cyradm-examples.md`.

## The three namespaces (RFC 2342)

Every mailbox a user can see falls into one of three categories:

- **Personal** — the user's own mailboxes, internally named `user/<name>`
  (e.g. `user/daniel`). This is what a client sees as just `INBOX` and its
  subfolders.
- **Other users** — mailboxes belonging to *other* users' personal
  namespace that have been explicitly shared with you (via ACL).
- **Shared** — mailboxes with no single personal owner, managed by admins.
  Not a naming convention: any mailbox **not** under `user/` is automatically
  shared namespace. `user` is the only reserved top-level name - beyond
  that, an admin can name a shared tree anything (`shared/announcements`,
  `lists/imap`, or no prefix at all).

## Display settings (client-facing only - don't affect the above)

- **`altnamespace: yes`** (our setting, the default) - personal subfolders
  show as siblings of `INBOX` (`Trash`, `Sent`) rather than children
  (`INBOX.Trash`). Only affects how a client's `LIST`/`NAMESPACE` response
  looks, not the internal mailbox name.
- **`unixhierarchysep: yes`** (our setting, the default) - hierarchy
  separator is `/` instead of `.`. Matters a lot here specifically because
  we use `virtdomains` - usernames/domains contain dots, and `/` avoids
  Cyrus having to escape them internally (swapping `.` for `^`, which some
  clients handle badly).
- **`userprefix`** / **`sharedprefix`** (`"Other users"` / `"Shared folders"`
  in our config) - just the display label for the "other users" and
  "shared" namespaces. Only takes effect because `altnamespace: yes` is on;
  purely cosmetic, no bearing on the real mailbox name.

## Creating a shared mailbox

Only an admin (listed in `imapd.conf`'s `admins:`) can create a new
top-level mailbox with no parent - a regular user has no rights at the
root of the tree:
```
cm shared/announcements
```
See `docs/cyradm-examples.md` for more `cyradm` examples.

## The ACL permission system

Every mailbox has an Access Control List: a set of (identifier, rights)
pairs deciding who can do what to it. Rights are a string of letters -
`l` (lookup), `r` (read/select), `s` (seen flag), `w` (other flags),
`i` (insert/append), `p` (post via LMTP), `k` (create submailboxes),
`x` (delete mailbox), `t` (delete messages), `e` (expunge), `a` (administer
- change the ACL itself). Full reference and `sam`/`setacl` syntax in
`docs/cyradm-examples.md`.

**`defaultacl`** (ours: `anyone lsr`, matching Cyrus's own default) is the
ACL automatically applied to any newly-created top-level (parentless)
mailbox. Concretely: a freshly `cm`'d shared mailbox is immediately
lookup+readable by every user on the server unless you explicitly lock it
down right after creating it (e.g. `sam shared/x anyone none` followed by
per-user grants).

Personal mailboxes work differently - the owner (`user/daniel`'s owner
being `daniel`) gets full rights on their own mailbox implicitly; sharing
a personal folder with someone else is just granting them an ACL entry on
it directly (that's what makes it show up under their "other users"
namespace).

## Hardcoded/special ACL identifiers

Alongside real usernames, three special identifiers are recognized as ACL
subjects:

- **`anyone`** - literally every user, **including the anonymous/unauthenticated
  user**. Commonly paired with the `p` (post) right to let external mail
  reach a mailbox via LMTP without anyone being logged in.
- **`anonymous`** - yes, this exists - specifically the anonymous/unauthenticated
  user, as opposed to `anyone` (everyone, anonymous included).
- **`group:<name>`** - a named group of users, e.g. `group:accounting`.
  What actually populates a group depends on the authorization backend
  configured (`unix`, `mboxgroups`, `krb5`, `pts`) - we haven't set any of
  this up, so group ACLs aren't usable in this deployment as-is.

**Why `anonymous`/`anyone` are mostly moot for us right now**: `imapd.conf`
has `allowanonymouslogin: no`, which refuses anonymous connections at the
server level, before any ACL is even consulted. So in practice, granting
`anyone` a right here only ever reaches *authenticated* users - the
anonymous half of that identifier's meaning never gets exercised on this
server.
