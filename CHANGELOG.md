# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-07-30

### Added

- Local distributed test nodes using modern OTP `:peer` and `:erpc`.
- Per-cluster linked ownership, supervision, dynamic membership, and member
  selection by struct, node, or peer PID.
- Code-path, Mix environment, logger, application configuration, application
  startup, and additional-file propagation.
- Distributed `:cover` integration with counter flushing during shutdown.
- Transactional startup, rollback, monotonic member names, checked remote setup,
  and bounded concurrent shutdown with forced cleanup.
- Validation for distribution mode, cluster options, names, prefixes,
  applications, files, environments, and member counts.
- A `hidden: true` cluster option for parallel tests that do not exercise
  `:global`.
- Per-cluster and per-stop timeout overrides for isolated failure-path tests.
- Parallel-safe test modules with isolated, tagged shutdown-timeout tests.

### Changed

- Kept VM-global coverage checks synchronous while allowing independent cluster,
  configuration, membership, distribution, and lifecycle tests to run in
  parallel.
- Limited the full suite to three concurrent ExUnit modules and kept its runtime
  below ten seconds on the development environment.
- Isolated ExDoc and its parser/makeup dependencies in the `:docs` environment,
  so normal compilation and tests do not compile documentation tools.

[Unreleased]: https://github.com/mindreframer/dev_cluster/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mindreframer/dev_cluster/releases/tag/v0.1.0
