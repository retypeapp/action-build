# Retype Build Action

A GitHub Action to build a [Retype](https://retype.com/) powered website. The output of this action is then made available to subsequent workflow steps, such as publishing to GitHub Pages using the [retypeapp/action-github-pages](https://github.com/retypeapp/action-github-pages) action.

## Introduction

This action runs `retype build` over the files in a repository to build a website in the form of a static html website that can be published to any website hosting solution available.

After the action completes, it will export the `retype-output-path` value for the next steps to handle the output. The output files can then be pushed back to GitHub, or sent by FTP to another web server, or any other form of website publication target.

This action will look for a [`retype.yml`](https://retype.com/configuration/project/) file in the repository root.

## Usage

```yaml
steps:
- uses: actions/checkout@v3

- uses: retypeapp/action-build@latest
```

### Optional: `setup-dotnet` step

It may be useful to include the [actions/setup-dotnet](https://github.com/actions/setup-dotnet) step before `retypeapp/action-build@latest`. With this, the Build Action can install the `dotnet tool` Retype package.

The workflow file above would then become:

```yaml
steps:
- uses: actions/checkout@v3

- uses: actions/setup-dotnet@v1
  with:
    dotnet-version: 7.0.x

- uses: retypeapp/action-build@latest
```

If this is not included though, the action will still work, but it may need to use the NPM package in case the installed .NET version is not the one required by Retype. When resorting to the NPM package it may take a bit longer to set up the workflow due to the larger download size. It may also be the case that the GitHub runner is an unsupported OS by the NPM packages; as long as it has .NET installed, Retype should work regardless of the OS. But the NPM package is built targetted to specific OS'es, namely Linux, Mac and Windows.

## Inputs

Configuration of the project should be done in the projects [`retype.yml`](https://retype.com/configuration/project) file.

### `config`

Specifies the path where `retype.yml` file should be located or path to the specific configuration file.

### `license`

Specifies the license key to be used with Retype.

```yaml
- uses: retypeapp/action-build@latest
  with:
    license: ${{ secrets.RETYPE_LICENSE_KEY }}
```

**NOTICE**: The `license` key value cannot be saved directly to your configuration file. To pass the license key to Retype during the build process, the value must be passed as a GitHub Secret. For information on how to store a secret on your repository or organization, see [RETYPE_SECRET](https://retype.com/configuration/envvars/#retype_secret) docs.

### `strict`

This config is Retype [!badge PRO](https://retype.com/pro/) only.

To enable [`--strict`](https://retype.com/guides/cli/#options-2) mode during build. Return a non-zero exit code if the build had errors or warnings.

```yaml
- uses: retypeapp/action-build@latest
  with:
    strict: true
```

## Examples

The following workflow will serve as our starting template for most of the samples below.

```yaml
name: GitHub Action for Retype
on:
  workflow_dispatch:
  push:
    branches:
      - main

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v3

      - uses: retypeapp/action-build@latest
```

Here are a few common workflow scenarios.

### Most common setup

```yaml
steps:
  - uses: retypeapp/action-build@latest
```

## Specify a Retype license key

If a `license` key is required, please configure using a GitHub Secret.

```yaml
- uses: retypeapp/action-build@latest
  with:
    license: ${{ secrets.RETYPE_LICENSE_KEY }}
```

For more information on how to set up and use secrets in GitHub actions, see [Encrypted secrets](https://docs.github.com/en/actions/reference/encrypted-secrets).

## Specify path to the retype.yml file

It is possible to point the directory where `retype.yml` is:

```yaml
- uses: retypeapp/action-build@latest
  with:
    config: my_docs
```

Or the full path (relative to the repository root) to retype.yml

```yaml
- uses: retypeapp/action-build@latest
  with:
    config: my_docs/retype.yml
```

The config file may have a different file name

```yaml
- uses: retypeapp/action-build@latest
  with:
    config: my_docs/retype-staging.json
```

In a bit more complex scenario where various repositories are checked out in a workflow. This may be useful, for instance, if retype documentation is generated from files across different repositories.

```yaml
- uses: actions/checkout@v3
  with:
    path: own-repository

- uses: actions/checkout@v3
  with:
    repository: organization/repository-name
    path: auxiliary-repository

- uses: retypeapp/action-build@latest
  with:
    config: own-repository/my_docs/retype.yml
```

## Passing the output path to another action

It is possible to get the output path of this step to use in other steps or actions after the `action-build` is complete by using the `retype-output-path` value.

```yaml
- uses: retypeapp/action-build@latest
  id: build1

- shell: bash
  env:
    MY_ENV_TO_RETYPE_PATH: ${{ steps.build1.outputs.retype-output-path }}
  run: echo "Retype output is available at '${MY_ENV_TO_RETYPE_PATH}'."
```

Other Retype actions within the workflow may consume the output of this action by using the `RETYPE_OUTPUT_PATH` environment variable.

It is required to upload the output with [actions/upload-artifact](https://github.com/actions/upload-artifact), as changes in the file system are not available across different GitHub action jobs. Then from the subsequent job(s), the artifact can be retrieved using the `download-artifact` action.

The following sample demonstrates the [`upload-artifact`](https://github.com/actions/upload-artifact) and [`download-artifact`](https://github.com/actions/download-artifact) actions.

## Uploading the output as an artifact

To use the Retype output in another job within the same workflow, or let an external source download it, it is possible to use [`actions/upload-artifact`](https://github.com/actions/upload-artifact) to persist the files. The uploaded artifact can then be retrieved in another job or workflow using [`actions/download-artifact`](https://github.com/actions/download-artifact)

```yaml
- uses: retypeapp/action-build@latest
  id: build1

- uses: actions/upload-artifact@v2
  with:
    path: ${{ steps.build1.outputs.retype-output-path }}
```

## Publishing to GitHub Pages

By using the Retype [retypeapp/action-github-pages](https://github.com/retypeapp/action-github-pages) action, the workflow can publish the output to a branch, or directory, or even a make a Pull Request. The website can then be hosted using [GitHub Pages](https://docs.github.com/en/github/working-with-github-pages/getting-started-with-github-pages).

The following sample demonstrates configuring the Retype `action-github-pages` action to publish to GitHub Pages:

```yaml
- uses: retypeapp/action-build@latest

- uses: retypeapp/action-github-pages@latest
  with:
    branch: retype
    update-branch: true
```

## Testing with a specific branch of the retypepp action

You can test with a specific branch of the retypapp action by replacing the `@latest` with the `@branch-name-here`.

```yaml
- uses: retypeapp/action-build@branch-name-here
```

## Build in `--strict` mode

Return a non-zero exit code if the build had errors or warnings. Set `true` to enable stict mode.

```yaml
- uses: retypeapp/action-build@latest
  with:
    strict: true
```