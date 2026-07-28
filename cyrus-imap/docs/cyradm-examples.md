# cyradm examples

Quick reference for `cyradm` against this deployment. Mailbox names use `/`
as the hierarchy separator (`unixhierarchysep: yes`) and internal personal
mailboxes are named `user/<username>` regardless of what the IMAP client
displays (that's `altnamespace` at work, client-side only).

## Connecting

```sh
docker exec -it <container> cyradm --user admin localhost
```

You'll see a self-signed certificate warning on every connection - that's
expected (see README's TLS certificate section) and not fatal:

```
verify error:num=18:self-signed certificate
```

It'll still prompt for the password. To silence the warning instead of
ignoring it, point `cyradm` at the cert directly as its own trust anchor:

```sh
docker exec -it <container> cyradm --user admin --cafile /etc/cyrus/tls/server.crt localhost
```

Once connected you get a `localhost>` prompt. All commands below run there.
Type `quit` or `exit` to leave.

## Listing mailboxes

```
lm                       # list all mailboxes admin can see
lm user/daniel*          # list a specific user's mailboxes
lam user/daniel          # list ACLs on a mailbox
```

## Creating mailboxes

```
cm user/newuser                    # create a personal INBOX for newuser
cm user/newuser/Archive            # create a subfolder
cm shared/announcements            # create a shared (non-personal) mailbox
```

In practice you shouldn't need `cm user/<name>` often - `autocreate_quota`
(see README) auto-creates a user's INBOX plus the configured subfolders
(`Trash`/`Spam`/`Sent`/`Draft`) the first time they successfully log in, no
admin action required.

## Deleting / renaming

```
dm user/newuser/Archive             # delete a mailbox
rm user/newuser/Archive user/newuser/OldArchive   # rename
```

Deleting a user's whole INBOX (`dm user/newuser`) deletes all their mail
permanently - `delete_mode: immediate` in `imapd.conf` means there's no
undelete window.

## Permissions (ACLs)

This is how folders end up under `Other users/` (or `Shared folders/`) for
someone else - sharing is just granting another user an ACL on your mailbox:

```
sam user/daniel/Archive admin lrswipkxtecda   # grant admin full rights
sam user/daniel/Archive otheruser lrs         # grant read-only (lookup/read/seen)
dam user/daniel/Archive otheruser             # revoke otheruser's access entirely
```

Common ACL letters: `l` (lookup/visible), `r` (read), `s` (seen/flags),
`w` (write flags other than seen/deleted), `i` (insert/append),
`p` (post via LMTP), `k` (create submailboxes), `x` (delete mailbox),
`t` (delete messages), `e` (expunge), `a` (administer/change ACLs).

## Quota

```
sq user/daniel STORAGE 102400              # cap storage at 100 MiB (value is in KiB)
sq user/daniel MESSAGE 5000                # cap message count at 5000, independent of size
sq user/daniel STORAGE 102400 MESSAGE 5000 # set both at once
lq user/daniel                             # show current quota usage
```

`STORAGE` and `MESSAGE` are independent resources - a mailbox can have a
limit on one, the other, both, or neither. `autocreate_quota` /
`autocreate_quota_messages` in `imapd.conf` just set these same two
resources automatically at the moment autocreate creates a mailbox, instead
of an admin running `sq` by hand afterward.

## Admin-only vs. per-user

Only usernames listed in `imapd.conf`'s `admins:` directive (currently
`admin`) can run `cm`/`dm`/`sam`/`sq` against mailboxes they don't own.
A regular user (e.g. `daniel`) can manage their own mailbox and anything
they've been granted `a` (administer) rights on, but nothing else.
