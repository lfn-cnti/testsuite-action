# CNTi Test Suite GitHub Action

Runs the [CNTi Test Suite](https://github.com/lfn-cnti/testsuite) against your CNF inside a
GitHub Actions job, so every pull request to your Helm chart or manifests is checked against
cloud native best practices.

By default the action creates a 3-node [kind](https://kind.sigs.k8s.io/) cluster, installs the
latest `cnti-testsuite` release (v2.0.0 or newer), deploys your CNF and runs the essential test set (the `cert` task).
It writes a job summary, annotates failed tests, uploads the results and the evidence bundle as an artifact and
fails the job when the CNF does not meet the objective of the run (for the essential tests: 15 of 19 passed).

## Usage

Helm chart repository — one step is enough:

```yaml
- uses: lfn-cnti/testsuite-action@v1
  with:
    helm_chart_dir: charts/coredns
```

Anything the suite supports (Helm repos, OCI charts, manifests, multiple deployments) via a
[`cnti-testsuite.yaml`](https://github.com/lfn-cnti/testsuite/blob/main/CNTI_TESTSUITE_YAML_USAGE.md):

```yaml
- uses: lfn-cnti/testsuite-action@v1
  with:
    cnf_config: ci/cnti-testsuite.yaml
    tests: workload
    extra_args: --strict
```

Image built in the same job — no registry round trip; load it into the kind cluster and
point the config at it:

```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    load: true
    tags: ghcr.io/example/my-cnf:ci
- uses: lfn-cnti/testsuite-action@v1
  with:
    cnf_config: ci/cnti-testsuite.yaml       # references ghcr.io/example/my-cnf:ci
    kind_load_images: ghcr.io/example/my-cnf:ci
```

Existing cluster (self-hosted runner with `$KUBECONFIG` set):

```yaml
- uses: lfn-cnti/testsuite-action@v1
  with:
    cnf_config: cnti-testsuite.yaml
    create_kind_cluster: false
```

## Inputs

| Input | Default | Description |
|---|---|---|
| `version` | `latest` | cnti-testsuite release tag, e.g. `v2.0.0` (v2.0.0 or newer) |
| `binary_url` | | URL of a release tarball to install instead of `version`, e.g. a prerelease on a fork, to try a build before its release |
| `attest` | `false` | attest the results file with GitHub artifact attestations, from the default branch (needs `id-token: write`, `attestations: write`) |
| `evidence_oci_ref` | | chart or image reference in a registry to attach the signed evidence to (cosign attestation, keyless), from the default branch (needs `id-token: write` and push access) |
| `evidence_oci_token`, `evidence_oci_username` | the job's token, the actor | registry login for `evidence_oci_ref`; the defaults work for ghcr.io with `packages: write` |
| `cnf_config` | | Path to a `cnti-testsuite.yaml`; takes precedence over `helm_chart_dir` |
| `helm_chart_dir` | | Local Helm chart directory; a minimal config is generated |
| `tests` | `cert` | Task to run: `cert` (the essential tests), `workload`, `all`, `static`, a category or a single test |
| `extra_args` | | Extra arguments, e.g. `--strict`, `--poc`, `--skip <test>` |
| `log_level` | | Suite log level (`debug`, `info`, …), exported as `CNTI_TESTSUITE_LOG_LEVEL` |
| `install_timeout` | | Seconds to wait for the CNF during `cnf_install` (`--timeout`) |
| `create_kind_cluster` | `true` | Create a kind cluster; `false` uses `$KUBECONFIG` |
| `kind_config` | | Custom kind config (default: 1 control-plane + 2 workers) |
| `kind_version` | | kind version; empty uses the [helm/kind-action](https://github.com/helm/kind-action) default |
| `kind_load_images` | | Local Docker images to load into the kind cluster (whitespace-separated) |
| `fail_on_failure` | `true` | Fail the job when the run exits non-zero |
| `upload_results` | `true` | Upload `cnti/results/` and `cnti/evidence/` as an artifact: every run's full evidence is downloadable from the run page, whether or not a badge or an evidence repository is set |
| `artifact_name` | `cnti-testsuite-results` | Artifact name |
| `badge_branch` | | Publish `cnti-badge.svg`/`.json` to this orphan branch with `GITHUB_TOKEN` (needs `permissions: contents: write`); default branch only |
| `gist_badge_id` | | Optional gist ID for a results badge on another repository |
| `gist_badge_secret` | | Token with `gist` scope |
| `gist_badge_filename` | `cnti_badge.json` | Badge file name in the gist |

One of `cnf_config` or `helm_chart_dir` is required.

## Outputs

| Output | Description |
|---|---|
| `status` | `passed`, `failed` or `error` |
| `exit_code` | `0` passed, `1` failed, `2` error, `64` usage error |
| `passed` / `max_passed` | Tests passed / maximum |
| `essential_passed` / `essential_max_passed` | Essential tests passed / maximum |
| `points` / `maximum_points` | Points scored / maximum |
| `criteria` | Pass criterion of the run as compact JSON (e.g. the essential-tests threshold of `cert`); empty when the task has none |
| `results_file` | Path to the results YAML |

```yaml
- uses: lfn-cnti/testsuite-action@v1
  id: cnti
  with:
    helm_chart_dir: charts/my-cnf
    fail_on_failure: false
- run: echo "${{ steps.cnti.outputs.essential_passed }} essential tests passed"
```

## Badge

No secrets needed: let the action publish the badge to an orphan branch of the repository
(one commit, replaced on every run of the default branch) and embed it from there:

```yaml
permissions:
  contents: write
# ...
- uses: lfn-cnti/testsuite-action@v1
  with:
    helm_chart_dir: charts/my-cnf
    badge_branch: badges
```

```markdown
![CNTi essential](https://github.com/<owner>/<repo>/raw/badges/cnti-badge.svg)
```

The badge shows the CNTi logo, the test set and the result, e.g. `CNTi essential 16/19` (tests passed / maximum for the task that ran; the `cert` task's set is named `essential`, any other task by its name), green when the run met its objective. It is written by the suite itself (`cnti-testsuite evidence`, v2.3.0 or newer), so every CI system gets the same badge. Pull requests never
touch the badge; only runs on the default branch publish it.

### Without write access to the repository

Some projects don't let workflows write to their repository. The gist variant keeps the
workflow at `permissions: contents: read`: the action writes the badge to a public gist
instead, and the README shows it through shields.io: the CNTi symbol in colour on a white
panel, the task and the result. Like the branch badge, only completed runs of the default branch update it.

1. Create a public gist with one file, e.g. `cnti_badge.json` containing `{}`, and note its ID.
2. Create a token that can write gists, e.g. a fine-grained personal access token with only
   the account permission **Gists: Read and write**, and store it as a repository secret,
   e.g. `CNTI_BADGE_GIST_TOKEN`. Tokens expire: when it does, the badge stops updating
   until the secret is renewed.

```yaml
permissions:
  contents: read
# ...
- uses: lfn-cnti/testsuite-action@v1
  with:
    helm_chart_dir: charts/my-cnf
    gist_badge_id: <gist id>
    gist_badge_secret: ${{ secrets.CNTI_BADGE_GIST_TOKEN }}
```

```markdown
![CNTi essential](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/<user>/<gist id>/raw/cnti_badge.json)
```

### From a private repository

A private repository cannot serve its badge from a branch, and a badge alone is not evidence a
reader can act on. With `evidence_repository` the action pushes the whole bundle to a public
repository you own, from runs of the default branch, with history:

- `cnti-badge.svg` and `cnti-badge.json`: the badge;
- the results file and its JUnit report;
- `cnti-evidence.json`: an in-toto Statement with the Test Result predicate, the results file as
  its subject by digest, and a `cnti` block with the suite version, task, status, score, run
  date, and the names of the files published and withheld;
- `config/`: the `cnti-testsuite.yaml` the CNF was installed from and every values file it names,
  bundled by the suite itself, so a reader sees what was set on top of the chart's defaults;
- any extra files you name in `evidence_files` (a README of the test setup, say).

The bundle comes from the suite's own `cnti-testsuite evidence` (v2.3.0 or newer). Never published: the suite's
logs (they stay in the job's artifact) and any file whose name matches `evidence_exclude`
(`*secret*` and `*credential*` by default); withheld names are listed in the statement. A file in
`evidence_files` is published verbatim: keep credentials in `--set` values from a secret, or in
excluded files.

1. Create a public repository for the evidence, e.g. `<owner>/cnti-evidence`.
2. Create a fine-grained personal access token with **Contents: Read and write** on that one
   repository, and store it as a secret of the private repository, e.g. `CNTI_EVIDENCE_TOKEN`.

```yaml
- uses: lfn-cnti/testsuite-action@v1
  with:
    cnf_config: .github/cnti/cnti-testsuite.yaml
    evidence_repository: <owner>/cnti-evidence
    evidence_token: ${{ secrets.CNTI_EVIDENCE_TOKEN }}
```

Each run lands in `cnti/<cnf name>/<run date>/` of that repository, and `cnti/<cnf name>/latest/`
always holds the badge of the newest run, for the README of the evidence repository or any
public page:

```markdown
![CNTi essential](https://github.com/<owner>/cnti-evidence/raw/main/cnti/<cnf name>/latest/cnti-badge.svg)
```

#### Prove where the evidence came from

With `attest: "true"` the action attests the results file with
[GitHub artifact attestations](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations):
the statement's Test Result predicate, signed with the workflow's identity and stored by GitHub.
A reader of the published bundle verifies it without access to your repository:

```
gh attestation verify cnti-testsuite-results-<timestamp>.yml \\
  --repo <owner>/<repo> --predicate-type https://in-toto.io/attestation/test-result/v0.1
```

(`--owner <org>` in place of `--repo` accepts any repository of an organisation. The predicate
type is needed: without it `gh` looks for a SLSA build provenance, which this is not. Add
`--format json` to see the signed statement and the workflow that produced it.)

The job needs `permissions: id-token: write` and `attestations: write`; the attestation is
made from runs of the default branch only, and the statement in the bundle then says
`provenance.method: github-attestation`. If the attestation fails, the bundle is published
unsigned (`provenance.method: none`) and the job goes on. The suite's USAGE describes the
other signing methods (Sigstore keyless, a project key) for CI systems that are not GitHub.

#### Evidence next to the chart

For a chart that lives in a registry, `evidence_oci_ref` attaches the evidence to it: the
statement's predicate, signed with the workflow's identity (Sigstore keyless) and stored as a
cosign attestation of the chart reference, so whoever pulls the chart pulls its evidence from
the same place, the way the suite's own `sbom_available` test reads SBOM attestations.

```yaml
permissions:
  contents: read
  id-token: write
  packages: write      # ghcr.io; another registry needs evidence_oci_token
# ...
- uses: lfn-cnti/testsuite-action@v1
  with:
    cnf_config: .github/cnti/cnti-testsuite.yaml
    evidence_oci_ref: ghcr.io/<owner>/charts/<chart>:<version>
```

A reader verifies and reads it with cosign:

```
cosign verify-attestation --type https://in-toto.io/attestation/test-result/v0.1 \\
  --certificate-identity-regexp '^https://github.com/<owner>/<repo>/' \\
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\
  ghcr.io/<owner>/charts/<chart>:<version> | jq -r .payload | base64 -d | jq .predicate
```

The reference must exist when the job runs: a chart the run installed from a registry (`registry_url`
in the config), or a run placed after the publish job. Each run adds an attestation (cosign stores
them as OCI referrers of the chart digest), so a chart carries its run history; the current verdict
is the newest by `run_date`:

```
cosign verify-attestation --type https://in-toto.io/attestation/test-result/v0.1 \\
  --certificate-identity-regexp '^https://github.com/<owner>/<repo>/' \\
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\
  ghcr.io/<owner>/charts/<chart>:<version> \\
  | jq -s 'map(.payload | @base64d | fromjson) | max_by(.predicate.cnti.run_date) | .predicate'
```

A package first pushed by a private
repository is private as well: make it public once (package settings) so that readers without
access can pull the attestation. The statement records the reference in
`provenance.files`, and `provenance.method: sigstore-keyless` with the workflow identity unless
GitHub attestations were made too, which it then keeps. The reference is recorded before anything signs
the statement, so the bundle's statement is the one both signatures cover; if attaching fails,
the reference is taken out again.

## Requirements

- `ubuntu-latest`, or any Linux x86_64/arm64 runner with Docker (for kind). `yq` is used to
  read the results file and is downloaded automatically when the runner lacks it. Helm is
  installed by the suite's own `setup` when missing.
- A full `cert` run (the essential tests) takes from a few minutes to about an hour depending on the CNF.

## Versioning

Use `@v1` to follow the latest 1.x release; pin `@v1.x.y` for reproducibility. The action
supports cnti-testsuite v2.0.0 and newer and tracks its results-file contract; a new major is released only when that
contract changes incompatibly.

## License

Apache-2.0
