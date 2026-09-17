# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.0]

Breaking. The library is now a job-for-job mirror of the GitLab CI template
library: jobs run inside the organisation build containers, monolithic jobs are
split into parallel ones with real `needs` edges, and configuration comes from
organisation variables rather than per-caller inputs.

Input count across the library: **275 -> 161**.

### Added

- `scripts/` — the shared shell the workflows run. The Trivy engine, changelog
  and migration guards, the lint wrappers, the buildah build and the Teams card
  are one implementation each, checked out at the exact ref the caller pinned
  (`github.job_workflow_sha`) and covered by shellcheck. `scan.yml` shrank from
  1552 lines to 250 as a result.
- `sbom.yml` — SBOM generation and its vulnerability scan as separate jobs
  (GitLab `SBOM:Generate` + `SBOM:Scan`), previously absent.
- `terraform-test.yml` — module test with a teardown job that runs only on
  failure (GitLab `Terraform:Module:Test` + `:Destroy`), previously absent.
- `mono.yml` — changed-project discovery returning a matrix. GitHub has no child
  pipelines, so the parent pipeline's job is to answer which projects changed.
- `ci.yml` and `cd.yml` — the library's own pipeline, the counterpart of
  `ci-templates/.gitlab-ci.yml`. It dogfoods the library's own `lint.yml`,
  `check.yml` and `release.yml`, adds actionlint and shellcheck as self gates,
  and tags, releases and posts the Teams card on merge to master. The released
  version is read from the new `VERSION` file.
- `templates/trivy-junit.tpl` — the JUnit report template, previously an inline
  YAML string.
- `fail-on-warnings` on `scan.yml` and `sbom.yml`, mirroring GitLab's
  `allow_failure: exit_codes: [2]`.
- `image-ref-digest` output on `docker.yml` and `buildah.yml`, so a scan can be
  pinned to the exact bytes that were built.
- `docker.yml` job `test` — the optional smoke test that runs a script inside the
  built image (GitLab `.Image:Test`), previously absent. Off by default.
- Eleven more outputs on `init.yml` (version suffix, push/dev repositories,
  major/minor, merged pull request number) that downstream workflows previously
  had to recompute.

### Changed

- Build and base image coordinates carry no library defaults. `TOOLKIT_BUILD_IMAGE`,
  `GO_BUILD_IMAGE`, `JAVA_BUILD_IMAGE`, `BUILDAH_BUILD_IMAGE`, `SONAR_SCANNER_IMAGE`,
  `BUILDKIT_IMAGE` and the five `*_MICRO_BASE_IMAGE` variables are now supplied entirely by
  the organisation. A container variable left unset fails the pull by name, which is a
  better failure than silently running a plausible-but-wrong image version.
- `actionlint` and `shellcheck` now run inside the organisation build container rather than
  being downloaded per run; they are expected to ship in `TOOLKIT_BUILD_IMAGE`.
- README rewritten against the GitLab library's structure: pipeline phases, the two-tier
  release model, an execution matrix, workflow DAGs, a full module catalog, the
  packaging-only Dockerfile and inverted `.dockerignore` standards, and ten
  project-level integration examples.
- Explanatory comments were removed from every `run:` block; only functional
  `# shellcheck` directives remain. Rationale now lives in the file header or
  above the job, not in the shell.
- Every job runs in an organisation build container (`bt-container`, `go`,
  `java-21-bt-container`, `buildah-podman`, `sonar-scanner-cli`) instead of
  installing its toolchain per run. `setup-python`, `setup-node`, `setup-go`,
  `setup-java`, `setup-uv`, `setup-helm`, `setup-crane` and `mikefarah/yq` are
  gone. The Docker build job is the deliberate exception — building an image
  needs the daemon on the runner.
- Image builds receive every organisation base image as a build argument, so a
  packaging Dockerfile pins nothing itself.
- `check.yml` is six parallel guard jobs plus a `verdict` job, instead of one job
  of `continue-on-error` steps. `lint.yml` is a matrix. Chart, language and
  Terraform workflows gained dependency/build/test/lint job splits with `needs`,
  so a failure costs one job rather than a whole sequential run.
- Configuration moved to organisation variables. See MIGRATION.md for the list.
- `IMAGE_REGISTRY_USERNAME` / `IMAGE_REGISTRY_PASSWORD` are used everywhere; the
  two deploy workflows previously called them `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`.

### Removed

- **BREAKING** — `terraform-module.yml`. Terraform consumes modules directly from git
  (`source = "git::<repo>//<path>?ref=<tag>"`), so packaging a tarball and publishing it
  duplicated what the git ref already provides, and added an artifact to maintain and
  version. The release tags the repository; consumers pin that tag with `?ref=`.
  `release.yml` no longer consolidates `TF.md`, which only that job produced (`TF_CVE.md`
  is unaffected).
- `python-test.yml`, `node-test.yml`, `golang-test.yml`, `java-test.yml` — the
  test job moved into the matching `*-build.yml`, next to a shared dependency
  job, matching the GitLab grouping.
- The `runner` input from every workflow, and the toolchain-version, cache-key
  and registry inputs that organisation variables now supply.

### Fixed

- `chart.yml` · `push` and `promote` declare `packages: write`, and `scan.yml` declares
  `checks: write`. All three used those capabilities without declaring the scope, which
  fails for any caller whose token is not already broad.
- README documents the caller-side `permissions:` block per scenario, and that a reusable
  workflow cannot raise the caller's token.
- Least-privilege `permissions:` added to seven jobs that were inheriting the default token
  scope (`ci`/`cd` version resolution, `check` verdict, and the three deploy jobs).
- Step summaries added to the six jobs that reported nothing on the run page: chart package,
  Node production install, Terraform init, release payload collection, and both ArgoCD
  deploy jobs — the last of which now states what was verified before anything is committed.
- `chart.yml` · `push` and `docker.yml` · `test` tolerate a skipped upstream explicitly
  instead of relying on their own `if:` happening to match the upstream's.
- Python dependency synchronization remains strictly frozen instead of retrying with a
  lockfile-mutating fallback.
- Dependency caches are now keyed by the lockfile hash (`uv.lock`, `package-lock.json`,
  `go.sum`, `pom.xml`) rather than a static prefix, so a dependency change invalidates
  the cache instead of silently reusing a stale one. The previous static keys bounded
  cache storage at the cost of correctness.
- The separate `python-uv-cache` artifact is gone: the dependency job publishes one
  cache that the build, test and lint jobs all restore, so nothing is copied twice.
- Language build artifact uploads include hidden files consistently for Python, Node,
  Go and Java.

## [2.0.0]

Breaking. The library no longer carries organisation-specific defaults, no longer exposes its own
toolchain as inputs, and no longer reports a failed step as a successful run. Input count across
the library: **283 -> 238**.

### Removed

- Every organisation-specific default. `registry` (7 workflows) and `helm-repository` (`init`) are
  now required with no default; so are `sonar-url`/`project-key`/`project-version` (`sonarqube`),
  `tag` (`check`), `gitops-repo`/`argocd-server`/`app-path` (`deploy-argocd-gitops`) and
  `image-repository` (`deploy-komodo-gitops`). A mandatory value should not have a default that
  silently publishes somewhere else.
- `candidate-pr-number` (`chart.yml`, `docker.yml`). Declared, documented, mapped to an env var and
  never read — the candidate-selection logic it described was never implemented.
- `allow-rebuild-on-missing-candidate` (`chart.yml`, `docker.yml`). A production release now always
  promotes the artifact the pre-merge pipeline scanned. This also made `docker.yml`'s "Build and
  Push Release Tags (Fallback)" step unreachable, so it is gone.
- `check-dependency` (`chart.yml`). A chart depending on a development registry is always rejected.
  The check no longer greps a hardcoded `helm/dev` string either — it reads the declared
  dependencies and compares them against the configured dev repository.
- `mode` (`check.yml`). The guards always assert an artifact is *new*; the `must-exist` direction
  existed to verify a release had landed and no caller used it.
- `.github/dependabot.yml` is now a full configuration, and `docs/dependabot.md` documents what a
  consumer repository needs — the library's own file is not inherited.
- `docs/recipes.md`: copy-paste end-to-end pipelines. Complete `pr.yml` and `release.yml` for Java,
  Go, Python, Node and a Node frontend+backend monorepo, the ArgoCD and Komodo deploys, and the
  on-demand `ops-*.yml` files, with the file layout and the five values to substitute. Every block
  is checked against the workflows' real contracts — unknown `with:` keys, missing required inputs,
  `needs.*.outputs.*` that do not exist — and actionlint-ed as a standalone workflow.
- Every `*-dev-repository` input, from `init`, `chart`, `docker`, `check`, `scan` and both deploys,
  along with `init`'s two matching outputs. A development repository is now derived as
  `<repository>/<dev-repository-suffix>`, where the suffix is an input defaulting to `dev`. Passing
  a repository and its dev twin let the two disagree; there is now one value per artifact type.
- `image-name` (`docker.yml`). The `image-name` *output* is already the full published reference
  (`registry/repo:tag`); the input was a second, cosmetic label printed once in the release notes.
- `major-version` / `minor-version` (`docker.yml`). Both were pass-throughs of a derivation the
  workflow can do itself from `image-tag`, and `init` still exports them for other consumers.
- `sbom-file`, `ignore-config-file` and `cache-key-prefix` (`scan.yml`). Now `sbom.cdx.json`,
  `ignored-cves.yml` and a single Maven cache namespace — `cache-key-prefix` also defaulted to
  `"java"` in a language-agnostic scanner.
- `run-install-check` (`golang-build`, `node-build`, `python-build`). Off by default and expressible
  through `build-command`.
- `cgo-enabled` (`golang-build`, `golang-test`). Set `build-env: CGO_ENABLED=1` instead; the
  workflows still default it to `0`, and `build-env` is exported first so it wins.
- `lint-command` (`node-lint.yml`). Biome always.
- `setup-node` / `node-version` (`python-test.yml`). A Python test workflow should not set up Node.
- `chart-dir` (`lint.yml`), replaced by the boolean `lint-chart`; the chart is read from `chart/`.
- `image-tar-path` and `image-tar-artifact` (`scan.yml`) and `save-image-tar` (`docker.yml`), with
  the tar export, upload, download and decompress steps. An image scan now always pulls from the
  registry, which is where the image already is.
- `image-prefix-repository` (`init.yml`). `image-repository` is now required and is the full path,
  so the prefix-concatenation branch it fed is gone too.
- `checks` (`check.yml`). Which guards run is now derived from the inputs the caller passes:
  `git-tag` and `changelog` always run, `chart` runs when a `chart-version` (or working-tree
  `Chart.yaml`) is present, `image` runs when `image-tag` and `image-repository` are set. A
  repository with no chart never passed one, so there was nothing the list could express that the
  inputs did not already say — and no way to soften a gate by dropping a word from it.
- `ignore-chart`/`ignore-docker` (`check.yml`, superseded by the derivation above), `job-name` and
  `changelog-version` (`check.yml`), `check-docs` and `readme-file-name` (`terraform-lint.yml`),
  `settings-file` (`sonarqube.yml`), `reclaim-paths` (`docker.yml`), `komodo-sync-timeout`
  (`deploy-komodo-gitops.yml`). All are fixed values now.
- `dry-run` and `extra-hosts` from both deploy workflows.
- `values-path`, `gitops-manifest-file`, `gitops-container-name`, `gitops-new-image` and
  `enable-github-deployment` from `deploy-argocd-gitops.yml`, plus the `*-dev-repository` inputs on
  both deploys. That workflow went from **26 inputs to 14**: values files are always `values.yaml`,
  raw-manifest patching is gone, and the workflow bumps a chart version at a yq path.
- Dead env aliases `PROJECT_PATH` (`chart.yml`, `check.yml`) and the unread `skipped` job output in
  `deploy-argocd-gitops.yml`.

Language runtime versions (`go-version`, `node-version`, `python-version`, `java-version`,
`java-distribution`) remain inputs: they describe the consumer's code, not the library's toolchain.

### Removed (outputs)

- Every output nothing consumed, across the library. `init` went from 25 outputs to 15
  (`version-suffix`, `registry`, `image-push-repository`, `chart-push-repository`,
  `major-version`, `minor-version`, `upstream-head-sha`, `merged-pr-number`); `chart` lost all
  three; `docker` kept only `image-ref-digest`, which `scan` consumes; `scan` lost all three; the
  four `*-test` workflows lost 22 `tests-*` / `coverage-percent` counters that no workflow or
  documented recipe read; both deploys and `terraform-module` lost theirs. Orphaned job-level
  outputs and the step machinery that fed them went with them, including `chart.yml`'s whole
  "Export Outputs" step.

### Security

- **Download checksum verification was removed** at the maintainer's request. `hadolint`, `trivy`,
  `betterleaks`, `helm-docs`, `terraform-docs` and the ArgoCD CLI are now fetched over HTTPS
  without comparing against the publisher's `sha256sum`. This is a deliberate reduction in
  supply-chain integrity: a corrupted or tampered release asset will no longer be detected.

### Performance

- **One shared Trivy cache across every scan type.** The cache key was
  `trivy-<scan-type>-<version>`, so a pipeline running image, config, licence and SBOM scans kept
  four separate copies of the same checks bundle and `trivy-java-db` and downloaded each
  separately. All four now share `trivy-db-<version>-<iso-week>`, ported from the GitLab
  library's single `trivy-db` cache. The week stamp bounds staleness that a fixed key would make
  permanent in GitHub, and `restore-keys` falls back to the previous week so a rotation refreshes
  instead of starting empty. The restore also no longer skips `license`, which left its save
  writing a cache its own restore never read.
- **New `trivy-cache.yml`**, the equivalent of the GitLab `Trivy:Cache:Warm` job: it downloads the
  misconfiguration checks bundle and, on a Java project, `trivy-java-db`, then publishes the shared
  cache before the scans run. Optional — without it the first scan of the week populates the cache
  itself. The vulnerability database is deliberately **not** cached, matching the GitLab design:
  Trivy refreshes it every few hours and a stale copy silently under-reports CVEs.
- **Licence and SBOM scans no longer fetch the vulnerability database.** Both are analyzer-only, so
  `--skip-db-update` is now unconditional for them rather than following `update-vuln-db`.
- **Every downloaded binary is cached.** `gotestsum`, `golangci-lint`, `gosec`, `yamllint` and
  `terraform-docs` re-downloaded on every run; each now restores from `actions/cache` and downloads
  only on a miss. `yamllint` was also unpinned and installed from PyPI on every run — it is now
  pinned via `yamllint-version`, as `gotestsum` is via `gotestsum-version`.

### Fixed

- **A rejected Komodo deploy reported success.** The trigger used `curl -f ... || true`, so a 4xx
  or 5xx produced an empty execution id, which the poller reported as `ACCEPTED_ASYNC` and exited
  with status 0. The HTTP status is now captured and a non-2xx fails the job.
- **A failed ArgoCD sync reported a healthy deployment.** Sync failure was a warning, after which
  `argocd app wait` returned immediately against the *previous* revision if the app was already
  Synced/Healthy. Sync failure is now fatal, and the observed revision is asserted against the
  commit this run pushed.
- **Releases published with no evidence.** Both artifact downloads were `continue-on-error` and
  nothing checked the result, so a GitHub Release — immutable once created — could be published
  with asset globs matching nothing. An empty collection is now a hard failure.
- **The SonarQube quality gate could not fail the job.** Nothing exited non-zero on
  `STATUS == ERROR`; the summary printed "Quality Gate — Failed" on a green run. A terminal
  `Enforce Quality Gate` step now fails the job, and an unreadable status fails it when
  `wait-for-quality-gate` is on. Coverage-download failure is fatal rather than silently producing
  a 0% measurement.
- **`docker.yml` could export a malformed image reference.** On the release-with-promotion path
  both build steps are skipped, so an unresolvable digest produced `registry/repo@`, which
  `scan.yml` and the deploy workflows then consumed. It now fails explicitly.
- **`terraform-lint.yml` claimed every check passed.** The `always()` summary hardcoded a tick for
  fmt, validate and tflint even when they failed. It now reads each step's outcome, and
  `tflint --init` no longer hides its error behind `2>/dev/null || true`.
- **Four caches never worked.** `scan.yml` referenced step id `cache_maven_repository` where the
  step is `cache-maven-repository`. `sonarqube.yml` dropped `runner.os` from its save key, so the
  cache could never be read back. `lint.yml` saved a hadolint binary that was never installed when
  Dockerfile linting was off. `terraform-lint.yml` cached a relative `.terraform` resolved against
  the workspace rather than `project-path`.
- `actions/setup-java` was pinned to both `v5` and `v6`, and `actions/download-artifact` to both
  `v7` and `v8`. Reconciled, and `.github/dependabot.yml` now groups action bumps.

### Changed

- **`chart.yml` is two parallel jobs.** `chart-build-push` (dependency update -> package -> push ->
  promote) is strictly fail-fast: a chart that fails to package is never pushed. `chart-hygiene`
  (`helm lint --strict`, dependency check, `helm-docs`) runs concurrently from its own checkout and
  reports independently. Previously this was one job that pushed *first* and ran hygiene
  afterwards, so a chart failing strict lint was already in the registry.
- **`dev-repository-suffix` is appended verbatim** and defaults to `/dev`, so `""` publishes
  candidates and releases to the same repository rather than forcing a separate one.
- **Tool versions stay inputs**, each with a default (`trivy-version`, `hadolint-version`,
  `terraform-version`, `golangci-lint-version`, `helm-docs-version`, `argocd-version` and the
  rest), so a consumer can pin or bump one without waiting for a library release. `helm-docs` and
  the ArgoCD CLI, previously hardcoded with no override at all, are now inputs too.
- **`init` `helm-repository` defaults to `helm`** and `image-repository` is required. The chart
  path is a convention worth standardising; the image path is not guessable.
- **Deploys always resolve `<repository>/dev`.** Stable and candidate artifacts are both mirrored
  there, so the prod-vs-dev routing and its four repository inputs are gone. To make that guarantee
  real, the dev mirror push in `chart.yml` and `docker.yml` is now **fatal** instead of a warning.
- **The ArgoCD approval gate moved to the job that writes.** The `environment:` gate was on
  `argocd-sync`, which runs *after* `gitops-commit` has already pushed to the GitOps repository.
  It is now on `gitops-commit`.
- **GitHub Deployment tracking is switched by `github-environment-name` alone.** Setting it creates
  the environment; leaving it empty does not. `github-environment-url` remains optional, matching
  GitHub, which does not require a URL.
- Crane is no longer installed on pull request runs (`chart.yml` gates on `is-release`,
  `docker.yml` on `is-release || save-image-tar`).
- `scan.yml`'s Maven cache restore is guarded to match its only consumer (license and sbom scans).
- `terraform-docs` is downloaded from its GitHub release and verified against the published
  checksum, matching every other tool download in the library.
- Secrets are declared explicitly with `required: true` in `chart`, `check`, `docker`, `scan`,
  `sonarqube` and both deploys, so a missing credential fails at workflow-call validation.
- Every `workflow_call` input now carries a `description`.

### Security

- Credentials no longer reach a command line anywhere: `helm registry login` uses
  `--password-stdin`, and the Trivy and ArgoCD tokens are read by those CLIs from the
  environment instead of being passed as flags. The Trivy command was previously logged
  *after* the token was appended to it.
- All third-party actions are pinned to a commit SHA with a version comment. Tool
  downloads (trivy, gitleaks, hadolint, helm-docs, argocd) are verified against the
  checksums each project publishes.
- Container promotion is digest-addressed: the candidate tag is resolved to a digest once
  and promoted from `repo@sha256:…`, so the bytes promoted are provably the bytes scanned.
  Chart promotion re-reads the digest immediately before pulling and fails if it moved.
- The Helm values override for a config scan is written outside the chart directory, so
  Trivy no longer picks it up as another file to scan.

### Performance

- Tag existence is checked with `git ls-remote` instead of a full-history clone.
  `check.yml`, `chart.yml` and `docker.yml` each used `fetch-depth: 0` to answer one
  question; `chart.yml` and `docker.yml` paid it on every pull request even though the
  gate only runs on a release.
- The Trivy vulnerability database is cached between jobs and runs. License scanning and
  SBOM generation pass `--skip-db-update --skip-java-db-update` — neither reads the
  database, and each was downloading several hundred megabytes per job.
- The `.yaml` scan report is no longer generated or uploaded. It was a re-serialisation of
  the JSON, 1.5-3x larger, produced for every scan type and read by nothing.
- Every job has a `timeout-minutes`. Without one a hung build or an ArgoCD wait that never
  settles holds a runner for GitHub's 360-minute default.

### Changed

- **Consumer pattern is now one workflow file per purpose** (`pr` / `release` /
  `ops-*`) instead of a single file behind a `workflow` dropdown. Skipped jobs are
  rendered by GitHub, so a single-purpose manual run previously displayed the whole
  graph greyed out under a run title identical to every other run.
- `init.yml` resolves upstream provenance on a release build (merged pull request,
  its head SHA and the run that built its artifacts) via a four-strategy chain, and
  exposes `merged-pr-number`, `upstream-head-sha` and `upstream-run-id`.
- Candidate discovery in `chart.yml` and `docker.yml` is scoped to the merged pull
  request and sorted numerically by run id. Prefix matching alone could promote an
  unmerged pull request's artifact, because registry tag order is lexical.
- Candidate suffix now uses `github.run_id` rather than `github.run_number`, which
  is per-workflow-file and would collide across the split workflows.
- `is-release` and the resolved push repositories are decided once in `init.yml`;
  consumers no longer re-derive routing from `github.ref`.
- Version discovery follows the reference precedence: the language manifest wins
  over `Chart.yaml`, and `Chart.yaml` uses `.appVersion` when a Dockerfile exists.
  Java versions are resolved with `mvn help:evaluate` instead of a text scrape.
- `release.yml` collects the pull-request run's scan and test reports via
  `upstream-run-id`, leads with the changelog, groups each artifact with its own
  scan report, and republishes the collected evidence on the release run.
- `deploy.yml` patches `.chart.repoURL` alongside `.chart.version`, supports a
  separate image values file, and derives branch and values-path defaults from
  `environment`.
- ArgoCD sync restored to the reference behaviour: `--hard-refresh`, `--operation`
  on wait, 600s timeout, and no `--prune --force`.
- `scan.yml` is a full port of the reference scan engine: ignore-list suppression,
  detailed markdown report with ignored reasons, JUnit conversion, stale-ignore
  detection, license classification policy, and a paste-ready baseline generator.
- Language modules: linters and tests are blocking, `NODE_ENV=production` during
  build, `uv sync --frozen` no longer falls back, Biome pinned and its config
  required, `MAVEN_OPTS=-Djava.awt.headless=true`.
- Report artifact retention raised from 7 to 30 days so a long-lived pull request
  still has evidence to collect at merge.

### Added

- `lint.yml` — hadolint, yamllint and markdownlint, none of which had been ported.
- Container smoke test (`image-test-script`) in `docker.yml`.
- Pre-deploy chart and image existence gates in `deploy.yml`.
- Git tag validation before promotion in `chart.yml` and `docker.yml`.
- `allow-rebuild-on-missing-candidate` (default `false`) — a release fails rather
  than silently rebuilding from source and publishing untested bytes.
- Branch-scoped buildx cache and centrally pinned base-image build args.

### Removed

- `promote.yml` — its promotion path is the one embedded in `chart.yml` and
  `docker.yml`; its unique behaviours (git-tag gate, hard failure on a missing
  candidate) moved there. It probed only for a `-rc` suffix this library never
  produces, so it could not locate its own artifacts.
- `license.yml` and `sbom.yml` — folded into `scan.yml`. Three implementations of
  the same engine produced three incompatible report shapes.
- All five composite actions under `.github/actions/` — referenced by nothing, and
  unreachable from a reusable workflow, whose checkout is the caller's repository.
- `fail-on-vulnerabilities`, which also disabled the ignore-reason governance
  check. Replaced by `skip-cve-scan`, an all-or-nothing kill switch.
- `ignore-git-tag`, which had no counterpart in the reference.

### Fixed

- `ignored-cves.yml` entries were parsed and never applied, so suppressions had no
  effect at all and `package: "*"` did not work.
- Every Trivy and Helm invocation was suffixed `|| true`; a scanner failure,
  timeout or auth error produced an empty result set and a passing scan.
- Ignore reasons were trimmed with `xargs`, which applies shell quote processing
  and rejected any reason containing an apostrophe.
- Findings were counted per occurrence rather than per unique id.
- Exit code 2 was written to an unread output while the step exited 0, so the
  warning state was invisible.
- A malformed `ignored-cves.yml` was silently treated as empty.
- `release.yml` downloaded artifacts without `merge-multiple`, so every lookup for
  a flat filename missed and the security section was always empty.
- Missing ArgoCD credentials reported `sync=Synced`, `health=Healthy` and exit 0.
- The changelog gate could not fail; a version bump with no changelog entry shipped
  the entire history as the release body.
- Chart and image existence checks were skipped on empty inputs and passed when
  credentials were missing.
- `helm-docs` was never installed, so the README check always passed.
- `helm dependency update` was skipped on the default branch, so a release could
  publish a chart with no subcharts.
- Chart promotion used `crane copy`, leaving the candidate version inside a chart
  tagged as the release. The candidate is now re-packaged at the release version.
- `org.opencontainers.image.created` was empty on every pull-request build.
- `IMAGE_NAME` was interpolated into published release notes but never defined.
- Corrected two typos in the JUnit template inherited from the reference, and moved it
  from an inline heredoc into a readable `TRIVY_JUNIT_TEMPLATE` env value. GitHub
  evaluates only `${{ }}` in env values and never shell-expands `${VAR}`, so the
  Go-template variables need no escaping and the indent-stripping `sed` is gone.
- `astral-sh/setup-uv@v10` does not exist as a tag - only `v10.0.0`/`v10.0.1` - so the
  reference would have failed to resolve at runtime. Now pinned to a SHA.
- `lint.yml` downloaded `hadolint-Linux-x86_64`; the published asset is lowercase
  `hadolint-linux-x86_64`, so the download 404'd.
- `LC_ALL=C` is set before the `comm` set operations, so their collation invariant holds
  structurally rather than by coincidence.

## [1.0.1] - 2026-08-31

### Changed

- **BREAKING** — registry inputs and secrets are provider-neutral. `ocr-registry` →
  `registry`, `ocr-image-repository` → `image-repository`, `ocr-prefix-image-repository`
  → `image-prefix-repository`, `ocr-helm-repository` → `helm-repository`,
  `ocr-dev-repository-suffix` → `dev-repository-suffix`; secrets `OCR_USERNAME` /
  `OCR_PASSWORD` → `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`. Every consumer must be
  updated in the same change — a stale `ocr-*` key is silently ignored by GitHub, so the
  workflow runs with an empty repository rather than failing.
- **BREAKING** — `base-image-build-args` removed in favour of a single `build-args`. It
  carried five pinned base-image tags as its default, so any Dockerfile that relied on
  them now falls back to its own in-file defaults. Pass them via `build-args` to keep the
  previous behaviour.
- **BREAKING** — `terraform-module.yml`'s provider input is now `required: true` with no
  default; `oci` as a default contradicted provider-neutrality.
- `init.yml` no longer emits a `version` output. It was wired to the same value as `tag`
  while being described as the base version, so the two could never diverge as intended.
  Use `tag`, or `image-tag` / `image-push-tag` for the base/suffixed distinction.
- `scan.yml` no longer accepts `annotate-findings`; per-finding annotations are always on.

### Fixed

- `init.yml`'s `master-branch-regex` is matched against `GITHUB_REF_NAME` (a short branch
  name), but its default had been changed to `^refs/heads/main$` — a pattern that can
  never match one. Protected non-default release branches silently stopped being treated
  as release branches. Now `^(.*/)?(main|master)$`, which also restores the original
  `*/master` intent.
- `docker.yml` declared the `build-caches` input as removed while keeping 74 lines that
  referenced it, so cache restoration was permanently skipped and `actionlint` failed on
  the library itself. The dead machinery is gone.
- `docker.yml`'s four `dependency-cache-*` inputs were declared but never read, and the
  README documented a `Restore Dependency Cache` step that was never implemented. Both
  removed.
- `image-test-shell` defaults to `bash` again; `/bin/sh` silently broke any smoke-test
  script using bashisms.

### Security

- All twelve registry logins now pipe the password with `printf '%s'` rather than `echo`,
  which appends a newline to the credential.
- `deploy-komodo-gitops.yml` no longer discards `docker login` failures with
  `2>/dev/null || true`, where a bad credential resurfaced later as "image not found".

## [1.0.0] - 2026-08-29

### Added

- GitHub Actions reusable workflows (`workflow_call`) under `.github/workflows/`:
  - `init.yml`: Comprehensive multi-framework version discovery (`Chart.yaml`, `package.json`, `pyproject.toml`, `pom.xml`, or explicit tag input), candidate suffix generation, and dev/prod repository matrix resolution.
  - `check.yml`: Release prerequisite validation, including Git tag check, OCI Helm chart version non-existence check, container image tag non-existence check, and Keep a Changelog extraction.
  - `docker.yml`: Standardized Docker / Buildx multi-arch builder with OCI container labels, registry caching, build-args, artifact downloading, release multi-tagging (`latest`, `MAJOR`, `MINOR`), and `IMAGE_INFO.md` digest generation.
  - `chart.yml`: Helm chart lifecycle management, including `helm lint --strict`, `helm-docs` README MD5 verification, dependency validation, OCI package pushing, and `CHART_INFO.md` generation.
  - `nodejs.yml`: Complete Node.js 24 lifecycle with `.npm` cache warming, Biome linting, offline install verification, and JUnit test reporting.
  - `python.yml`: Python 3.12 lifecycle with `uv` cache warming, multi-linters (Ruff, MyPy, ISort, PyCodeStyle), and pytest execution with JUnit reports.
  - `java.yml`: Java 25 / Temurin lifecycle with Maven `.m2` caching, dependency pre-download, compilation, and Surefire JUnit test reporting.
  - `scan.yml`: Trivy unified security scanner engine supporting container image, Helm chart config, license, and CycloneDX SBOM scans with `ignored-cves.yml` reason validation (10+ characters) and exit code evaluations.
  - `license.yml`: Reusable Trivy filesystem open-source license compliance scanner with category risk analysis.
  - `sbom.yml`: CycloneDX SBOM generation (`trivy fs --format cyclonedx`) and package inventory CVE scanning.
  - `secret-scanning.yml`: Betterleaks / Gitleaks secret detection across complete repository commit history.
  - `sonarqube.yml`: SonarScanner CLI integration and automated Quality Gate enforcement with GitHub metadata.
  - `promote.yml`: Layerless production promotion using Crane for OCI label mutation and alias tagging, Helm OCI chart promotion, and GitHub Release audit log updating.
  - `deploy.yml`: GitOps ArgoCD deployment with authenticated clone, YAML spacing-preserving diff/patch updates, commit authorship, and multi-app health/sync verification.
  - `release.yml`: Consolidated GitHub Release publisher with changelog notes, container image details, Helm chart details, security scan summaries, and asset attachment.
