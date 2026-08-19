# Plan 10 — deployment guides

## Why this plan exists

The review notes ask for deployment guides covering the cloud services
popular with Elixir developers, and ask specifically whether the
application can be deployed on Coolify and if so how.

The short answer to the Coolify question is yes. The longer answer,
with the specific traps this application sets, is the substance of this
plan.

## What already exists to build on

Nothing deployment related is in the repository: no container file, no
release configuration, no platform manifest, no toolchain version file.
The release generator has never been run.

But the runtime is more ready than that suggests, and the guides should
build on what is there rather than reinventing it.

- Migrations run on boot inside a release. The migrator is in the
  supervision tree and skips itself unless the release name variable is
  set, so a deployment needs no separate migration step.
- The server only starts when the server variable is set, which is the
  standard release gate.
- The asset deployment alias exists and produces a digested manifest,
  which production configuration already expects.
- There is a real health endpoint. It distinguishes liveness, which
  touches no dependency, from readiness, which checks the database and
  the job supervisor, and it returns the appropriate status code. The
  end to end suite already waits on it, so it is known to work.
- Clustering by DNS query is already wired.

## What has to be created first

### A release and a container image

Run the release generator with the container option, then review what
it produces rather than accepting it. It gives a multi stage build:
compile with the full toolchain, run on a slim base. Add an ignore file
so the build context excludes the build directory, the local database
files, the end to end dependencies and the version control directory.

Points to check in the generated file:

- the asset deployment alias runs in the build stage, before the
  release is assembled;
- the runtime stage carries the locale data the application needs, and
  the time zone database, since dates are rendered per locale;
- the image runs as a non root user;
- a health check is declared against the health endpoint.

Add a toolchain version file so the image, the change gate and a
developer machine agree on the Erlang, Elixir and Node versions.

### Configuration contract

Document the environment variables in one table that every guide refers
to, rather than repeating them per platform: the secret key base, the
host, the port, the server flag, the database connection, the pool
size, and the cluster query. State which are required and what happens
when one is missing, since two of them raise at boot deliberately.

## The guides

Each guide follows the same shape so they can be compared: what you
need, how the image is built, the environment variables, the database,
migrations, the health check, logs, and what does not work.

They are authored as pages of the developer guide and published
by plan 08, so they live under `docs/` rather than being
duplicated in the README.

### Coolify

Coolify's own documentation covers Phoenix through its automatic build
pack, listing the production environment, the secret key base, the
database URL and exposing port four thousand [coolify]. There is also a
community walkthrough of deploying Phoenix on a Hetzner server with
Coolify [hetzner].

The recommendation for this project is to use the container file rather
than the automatic build pack. The automatic path is slower and can
saturate the processor on a small virtual server, and this application
needs specific runtime pieces in the image anyway. Document the
container route as primary and mention the automatic route as a
fallback.

Coolify specifics to cover: attaching a managed PostgreSQL and where
its connection URL appears, setting the health check path, configuring
the persistent volume if SQLite is retained, and the reverse proxy in
front, which matters for the redirect trap below.

### Fly.io

The most common target for Elixir. Cover the application manifest, the
managed PostgreSQL, secrets, the release command, regions and the fact
that clustering between machines is straightforward, which makes this
the easiest platform on which to run more than one node.

### Render

Container based, straightforward, managed PostgreSQL. Cover the health
check path and the fact that clustering is not available, which makes
the single node caveats below binding.

### Gigalixir

Elixir specific, so releases and clustering are first class. Worth
including precisely because it handles the distribution concerns the
others do not.

### A plain virtual server

The option many people actually choose. A compose file with the
application, PostgreSQL and a reverse proxy terminating TLS, plus
backups and log rotation. This is also the honest baseline: if the
application deploys here, it deploys anywhere.

## Gotchas this application specifically has

This section is the value of the document. Each item is real and
present in the code today.

### The health probe is redirected

Production configuration forces TLS, rewriting on the forwarded
protocol header. The exclusion for the health path is present in the
file but commented out.

The effect: a platform health probe that speaks plain HTTP and does not
set the forwarded protocol header receives a redirect rather than a
status. Depending on the platform, the deployment then never becomes
healthy, which looks like the application failing to start.

Either uncomment the exclusion, or document per platform that the probe
must use TLS or must set the header. Uncommenting is recommended: a
health endpoint returns no sensitive data.

### SQLite in a container needs a volume

If SQLite is retained in production, the container needs persistent
storage, and the volume must cover the write ahead log and shared
memory files beside the database, not only the database file itself,
because the journal mode is write ahead logging. Mounting only the
database file loses data on restart.

Once plan 09 lands, PostgreSQL is the recommended production database
and this becomes a caveat for the small single node case rather than
the default path.

### Rate limits do not aggregate across replicas

Rate limiting uses an in memory table local to each node. With more
than one replica, each enforces the limit independently, so the
effective limit is multiplied by the replica count. Document it, and
note that a shared backend is the fix if that matters.

### Session processes assume one node

Each live retrospective is a process registered locally and supervised
locally. With more than one replica and no clustering, two participants
routed to different instances join two different sessions and never see
each other.

Running more than one replica therefore requires real clustering, not
merely a load balancer. The DNS cluster query is already wired, so the
platforms that support it are the ones where multiple replicas are
safe. On the others, run one replica and say so.

This is the most important operational fact in the whole document and
it should be stated near the top of every guide, not buried.

### Secrets

The key base is hardcoded in the development, test and end to end
configurations, which is appropriate for those environments. Say so
explicitly, so nobody copies the pattern into production. Production
reads it from the environment and raises without it.

## Operating the application

Short sections that turn the guides into something usable after the
first deployment.

- Migrations: they run on boot. Explain what that means for a rollback,
  and how to run them by hand from a release shell if needed.
- Backups: how to take and restore one for each database, and a note
  that an untested backup is not a backup. One of the documented
  traceability gaps is about backup ageing, so this section is also
  where that gap gets a real answer.
- Logs: the application emits structured logs through a custom
  formatter, and card text and personal data are deliberately redacted
  before logging. Say what is and is not in the logs.
- Monitoring: what to watch, starting with the readiness endpoint and
  the job queues.
- Scaling: vertical first, then the clustering discussion above.

## Verification of plan 10

- The image builds from a clean checkout and starts with only the
  documented variables set.
- The application is actually deployed to at least one platform and a
  full retrospective is run against it, including a second participant
  in another browser, which is what proves the realtime path works
  behind a real proxy.
- The health probe returns success over the platform's own check,
  which proves the redirect trap is resolved.
- Migrations are observed running on first boot in the logs.
- A backup is taken and restored into a fresh database.
- Each guide has been followed end to end by someone other than its
  author, or is clearly marked as untested.

[coolify]: https://coolify.io/docs/applications/phoenix
[hetzner]: https://elixirforum.com/t/tutorial-deploy-phoenix-1-8-with-coolify-on-hetzner/71908
