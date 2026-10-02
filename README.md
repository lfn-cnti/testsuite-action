# CNTi Test Suite GitHub Action

Runs the [CNTi Test Suite](https://github.com/lfn-cnti/testsuite) against your CNF inside a
GitHub Actions job, so every pull request to your Helm chart or manifests is checked against
cloud native best practices.

By default the action creates a 3-node [kind](https://kind.sigs.k8s.io/) cluster, installs the
latest `cnti-testsuite` release (v2.0.0 or newer), deploys your CNF and runs the certification (`cert`) test set.
It writes a job summary, annotates failed tests, uploads the results YAML as an artifact and
fails the job when the CNF does not meet the certification objective.

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
| `cnf_config` | | Path to a `cnti-testsuite.yaml`; takes precedence over `helm_chart_dir` |
| `helm_chart_dir` | | Local Helm chart directory; a minimal config is generated |
| `tests` | `cert` | Task to run: `cert`, `workload`, `all`, `static`, a category or a single test |
| `extra_args` | | Extra arguments, e.g. `--strict`, `--poc`, `--skip <test>` |
| `log_level` | | Suite log level (`debug`, `info`, …), exported as `CNTI_TESTSUITE_LOG_LEVEL` |
| `install_timeout` | | Seconds to wait for the CNF during `cnf_install` (`--timeout`) |
| `create_kind_cluster` | `true` | Create a kind cluster; `false` uses `$KUBECONFIG` |
| `kind_config` | | Custom kind config (default: 1 control-plane + 2 workers) |
| `kind_version` | | kind version; empty uses the [helm/kind-action](https://github.com/helm/kind-action) default |
| `kind_load_images` | | Local Docker images to load into the kind cluster (whitespace-separated) |
| `fail_on_failure` | `true` | Fail the job when the run exits non-zero |
| `upload_results` | `true` | Upload `cnti/results/` as an artifact |
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
| `criteria` | Pass criterion of the run as compact JSON (e.g. the `cert` threshold); empty when the task has none |
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
![CNTi cert](https://github.com/<owner>/<repo>/raw/badges/cnti-badge.svg)
```

The badge shows the CNTi logo, the task and the result, e.g. `CNTi | cert | 16/19` (tests passed / maximum for the task that ran), green when the run met its objective. Pull requests never
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
![CNTi cert](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/<user>/<gist id>/raw/cnti_badge.json)
```

## Requirements

- `ubuntu-latest`, or any Linux x86_64/arm64 runner with Docker (for kind). `yq` is used to
  read the results file and is downloaded automatically when the runner lacks it. Helm is
  installed by the suite's own `setup` when missing.
- A full `cert` run takes roughly 20–40 minutes depending on the CNF.

## Versioning

Use `@v1` to follow the latest 1.x release; pin `@v1.x.y` for reproducibility. The action
supports cnti-testsuite v2.0.0 and newer and tracks its results-file contract; a new major is released only when that
contract changes incompatibly.

## License

Apache-2.0
