# Contributing

Pull requests and pushes to `main` run the repository's deterministic,
non-live lifecycle gates through `scripts/check.sh`. The CI job proves:

- shell syntax and the repository-owned fleet skill contract;
- the canonical lifecycle interface, stable evidence schema, gate statuses, and
  incomplete-outcome behavior through black-box tests;
- required-secret manifest consistency without decrypting production secrets;
- Nix formatting, flake checks, every declared host's system evaluation, and
  evaluated generated-consumer assertions;
- immutable OCI deployment references, except for exact entries in
  `policy/deployment-pin-exceptions.json` that document an owner, reason, and
  review date.

CI has no production credentials and must not contact production hosts. It does
not build or dry-activate hosts, create backups, switch configurations, verify
live routes or services, select snapshots, restore data, or provision machines.
Those remain guarded operator acceptance steps under `PRINCIPLES.md` and the
host-specific lifecycle workflow. A failed required CI command fails the job;
there is no CI representation that converts a failed, blocked, or unrun required
gate into a complete lifecycle outcome.
