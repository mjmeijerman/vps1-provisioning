# vps1-provisioning

Provisioning for `vps1.markmeijerman.nl`.

    make provision-prod

Requires the vault password for `group_vars/production/*_secure.yml`.


## Vault

The password lives in one file outside the repository:

    install -m 600 /dev/null ~/.ansible/vault-pass-vps1
    # then put the password in it, on one line

`make provision-prod` uses that file when it exists and falls back to
`--ask-vault-pass` when it does not, so a machine without it still works. The
test suite and the CI checks never need it. Nothing in this repository may ever
contain the password itself: it decrypts the DKIM key and the database
credentials.

Extra arguments go through untouched:

    make provision-prod ARGS="--limit vps1 -vv"
    make provision-prod-dry        # reports changes, changes nothing


## Speed

Every run prints its slowest tasks when it ends (`profile_tasks` in
`ansible.cfg`). Read that list before optimising anything.

A full run went from 365s to 154s. What that took, so nobody re-does it:

- **SSH multiplexing.** One connection for the whole play instead of one per
  task; there are 245 of them.
- **Fact caching.** Cached for 30 minutes in `.ansible/facts`, so a second run in
  that window skips both fact gathers.
- **No `stat` on a 2 GB file.** The module hashes the file to report a checksum
  by default, and `/swapfile` takes eight seconds to hash. `get_checksum: false`
  where nothing reads the checksum.
- **The firewall is applied only where it differs.** Every `ufw` call that
  changes the ruleset rewrites the whole iptables set, and the
  `community.general.ufw` module runs four extra subprocesses per rule, so five
  unchanged rules cost 13 seconds and reloaded the firewall for a no-op.
- **The vim alternatives are one shell run**, not eight module calls that mostly
  change nothing.
- **One deb.sury.org source.** `f500.php8` used to add an unsigned second one
  after `php_sury_repo` had cleaned up, so apt read the repository twice and
  warned on every call.
- **`f500.debian` runs once.** It was listed twice in `playbook.yml`.
- **`cache_valid_time` on every apt task**, and one apt call where a role used to
  make three.
- **One call to remove the anonymous database users**, not one per host entry.

Checks that need no vault, and no host:

    make lint            # ansible-lint, our own files only
    make syntax-check    # parse the playbook


## What this box runs

| Piece | Role | Notes |
|---|---|---|
| Static and PHP sites | `f500.nginx`, `f500.php8`, `webserver` | vhosts from `group_vars/production/main.yml` and `websites.yml` |
| MariaDB | `HanXHX.mysql` | |
| Docker | `install_docker` | Docker Engine + compose v2 from Docker's repository |
| Bakmark staging | `install_docker` + `webserver` | container on `127.0.0.1:8090`, nginx in front |

Every role is in `roles/`. Nothing is installed from Galaxy except collections,
so `ansible.cfg` has no `roles-galaxy/` on its `roles_path` and there is nothing
to shadow what this repository owns.


## Roles we own

All of them. `roles/*` used to be either ours or downloaded from Galaxy, and
almost every downloaded role needed a change the published version does not
have — so every role lives here now, and `meta/main.yml` records the version
each came from. `make update-collections` installs collections and nothing else.

Four of them need reading before they are edited:

- `HanXHX.mysql` is MariaDB on a single node. The galera and replication
  branches were removed, along with the defaults only they used; the config
  templates and the databases/users path are unchanged.
- `geerlingguy.certbot` keeps its snap, source and standalone paths, but this
  box uses the package plus the webroot method. `certbot_auto_renew` is off:
  `lets_encrypt` runs its own renewal hook.
- `f500.ufw` applies the rules with a shell script that asks `ufw --dry-run`
  first, instead of the `ufw` module per rule. It is the only role here that can
  lock you out of the box, so run it on its own if you change it.
- `f500.php8` deliberately does **not** add the deb.sury.org repository:
  `php_sury_repo` owns that, with a signed-by keyring.


## A new machine

Role order is load-bearing. The first play sets up apt sources (the sury
repository before anything reads the apt cache), then base packages, MariaDB,
nginx, PHP, the deploy account, Docker, mail and logging. The second play adds
the web users, Certbot and the certificates. Changing the order means checking
these dependencies:

- `php_sury_repo` refreshes the apt cache immediately after writing its source.
  As a handler it ran at the end of the play, after `f500.php8` had asked for
  packages that only exist in that repository.
- `deploy_account` runs before `install_docker`: that role adds the account to
  the docker group, creates directories owned by it, and clones the application
  repositories over SSH as it. It is also what puts github.com in
  `known_hosts` and installs the deploy key the clone authenticates with.
- `HanXHX.mysql` runs before `webserver`: the WordPress tasks need the database
  and user to exist, and `install_apt_packages` runs before both, because the
  web tasks set ACLs.
- `geerlingguy.certbot` installs the package before `lets_encrypt` calls it.

Two things the playbook cannot do for you:

- **DNS has to point at the box already.** `lets_encrypt` stops nginx, requests
  the certificates and starts it again. Without a resolving name the request
  fails and nginx stays down.
- **The control machine needs `~/.ssh/id_ed25519.pub`**, which `webserver`
  installs for the deploy account.

After a rebuild, flush the fact cache: facts are cached for 30 minutes per
inventory name, so a reinstalled box can be provisioned with the old one's:

    make provision-prod ARGS=--flush-cache


## Docker applications

`install_docker` owns the runtime and the directories a container writes to.
The containers themselves are **not** Ansible's job: a deploy replaces them, and
a playbook that also manages them would fight the deploy for the same state.

What the role creates, and why:

- `/var/lib/bakmark-staging`, owned by uid 1000 with mode 0700. The container
  runs as `node` (uid 1000); if Docker created this directory it would be
  root-owned and the first signup would fail on a permission error.
- `/srv/bakmark`, a checkout owned by `deploy`, so the deploy script can
  `git reset --hard` in it without root.
- `deploy` in the `docker` group, so deploys need no password.

Deploying is the application's own script, run by CI or by hand:

    # from a checkout of the app
    ./deploy.sh

See the `bakmark` repository's README.


## Adding a site

`group_vars/production/main.yml` holds the redirects,
`group_vars/production/websites.yml` the vhosts. There are three lists:

| List | Template | For |
|---|---|---|
| `nginx_server_templates_redirects` | `redirect.conf.j2` | a domain that just 301s or 302s |
| `nginx_server_templates_websites` | `https.conf.j2`, `wordpress-https.conf.j2` | files on disk, optionally PHP |
| `nginx_server_templates_proxies` | `proxy-https.conf.j2` | an app on loopback, e.g. a container |

`server_templates` is the aggregate, and it is what the nginx and letsencrypt
tasks loop over. A list that is not added to it is silently ignored by both, so
a vhost can exist in config and nowhere else.


## Mail

`mail_server` installs Postfix and OpenDKIM so the application can send through
`127.0.0.1:25`. Per D6 there is no ESP and no relay: the SPF and DKIM signals
are ours.

Postfix is `loopback-only` and relays for `127.0.0.0/8` and `::1` only. It has
no submission or smtps service, because no user authenticates to this box.

The DKIM key is generated once and **never regenerated**. Rotating it means a
DNS change plus a window where signatures fail, so it must not happen because a
playbook ran again. Delete the key deliberately if it ever leaks.

### DNS the mail needs

The role prints these at the end of a run. All four are required:

| Record | Value |
|---|---|
| `TXT default._domainkey.news.bakmark.nl` | the content of `/etc/opendkim/keys/news.bakmark.nl/default.txt` |
| `TXT news.bakmark.nl` | `v=spf1 ip4:5.79.100.71 -all` |
| `TXT _dmarc.bakmark.nl` | `v=DMARC1; p=none; rua=mailto:hello@bakmark.nl` |
| `PTR 5.79.100.71` | `mail.bakmark.nl` (LeaseWeb portal) |

Until SPF and DKIM exist, mail leaves correctly signed but unauthenticated:
receiving servers have nothing to check the signature against and treat it as a
cold IP, which is the worst case D6 describes.

### Before the form goes live

Send to a mail-tester.com address and require **≥9/10**, then send to a real
Gmail and Outlook address and check the folder. Both, every time the MTA config
changes.

## Logs

Everything is bounded. That is the whole point: the box had 5 GB of `/var/log`
on a 59 GB disk before any container existed.

| What | Where | Kept |
|---|---|---|
| systemd journal | `journalctl` | 500 MB / 7 days |
| nginx | `/var/log/nginx/*.log` | 14 rotations, compressed, 30 days |
| containers | `docker compose logs` | 10 MB x 3 per container (`daemon.json`) |
| failed logins | `/var/log/btmp` | 4 monthly rotations |
| daily summary | `/var/log/logwatch/yesterday.html` | 14 days |

### Knowing something broke

`/etc/cron.hourly/health-check` writes only when something is wrong:

- disk above 85%
- any of nginx, mariadb, docker, postfix, opendkim not running

It mails `logging_alert_email`. Silence means healthy, so an empty inbox is the
good outcome, not a sign the check stopped running. Verify with:

    sudo run-parts --test /etc/cron.hourly   # is it registered
    sudo /etc/cron.hourly/health-check       # prints only on a problem

Application errors are in the container's own log, which is also what
`deploy.sh` prints when a rollout fails its health check:

    docker compose -f /srv/bakmark-production/docker-compose.yml logs --tail 100 bakmark
