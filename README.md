# vps1-provisioning

Provisioning for `vps1.markmeijerman.nl`.

    make provision-prod

Requires the vault password for `group_vars/production/*_secure.yml`.

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

`roles-galaxy/` is downloaded by `make update-ansible-roles` and is overwritten
on every update. Fixes that have to survive belong in `roles/` or in
`group_vars/`, not there.


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
