# Retype Build Action

A GitHub Action to build a [Retype](https://retype.com/) powered website. The output of this action is then made available to subsequent workflow steps, such as publishing to GitHub Pages using the [retypeapp/action-github-pages](https://github.com/retypeapp/action-github-pages) action.

## Introduction

This action runs `retype build` over the files in a repository to build a website in the form of a static html website that can be published to any website hosting solution available.

After the action completes, it will export the `retype-output-path` value for the next steps to handle the output. The output files can then be pushed back to GitHub, or sent by FTP to another web server, or any other form of website publication target.

This action will look for a [`retype.yml`](https://retype.com/configuration/project/) file in the repository root.

## Usage

```yaml
steps:
- uses: actions/checkout@v4

- uses: retypeapp/action-build@latest
```

### Optional: `setup-dotnet` step

It may be useful to include the [actions/setup-dotnet](https://github.com/actions/setup-dotnet) step before `retypeapp/action-build@latest`. With this, the Build Action can install the `dotnet tool` Retype package.

The workflow file above would then become:

```yaml
steps:
- uses: actions/checkout@v4

- uses: actions/setup-dotnet@v4
  with:
    dotnet-version: 9.0.x

- uses: retypeapp/action-build@latest
```

There is a small performance gain if a `dotnet` environment is configured as the package download is smaller, but `dotnet` is not required and can be excluded.

## Inputs

Configuration of the project should be done in the projects [`.github/workflows/retype-action.yml`](https://retype.com/guides/github-actions/#retype_secret) file.

### `output`

Custom folder to store the output from the Retype build process. Default is `""` (empty).

```yaml
- uses: retypeapp/action-build@latest
  with:
    output: my_output_directory/
```

### `secret`

License key to use with Retype. The Retype license key is private. 

Please store your license key as a GitHub [Secret](https://retype.com/guides/github-actions/#retype_secret).

```yaml
- uses: retypeapp/action-build@latest
  with:
    secret: ${{ secrets.RETYPE_SECRET }}
```

The `secret` can also be set using `env` Environment variables.

```yaml
- uses: retypeapp/action-build@latest
  env:
    RETYPE_SECRET: ${{ secrets.RETYPE_SECRET }}
```

**IMPORTANT**: The `secret` value cannot be saved directly to your workflow configuration file. To pass a license key to Retype during the build process, the value must be passed as a GitHub Secret. For information on how to store a secret on your repository or organization, see [RETYPE_SECRET](https://retype.com/guides/github-actions/#retype_secret) docs.

### `password`

Private password used to generate private and protected pages. See additional docs on how to configure [`password`](https://retype.com/guides/github-actions/#retype_password). Default is `""` (empty).

```yaml
- uses: retypeapp/action-build@latest
  with:
    password: ${{ secrets.PASSWORD }}
```

The `password` can also be set using `env` Environment variables.

```yaml
- uses: retypeapp/action-build@latest
  env:
    RETYPE_PASSWORD: ${{ secrets.RETYPE_PASSWORD }}
```

### `strict`

This config is Retype [!badge PRO](https://retype.com/pro/) only. Default is `false`.

To enable [`--strict`](https://retype.com/guides/cli/#options-2) mode during build. Return a non-zero exit code if the build had errors or warnings.

```yaml
- uses: retypeapp/action-build@latest
  with:
    strict: true
```

### `override`

JSON configuration overriding project config values. Default is `""` (empty).

```yaml
- uses: retypeapp/action-build@latest
  with:
    override: '{"url": "https://example.com"}'
```

### `verbose`

Enable verbose logging during build process. Default is `false`.

```yaml
- uses: retypeapp/action-build@latest
  with:
    verbose: true
```

### `config_path`

Specifies the path where `retype.yml` file should be located or path to the specific configuration file. Default is `""` (empty).

May point to a directory, a JSON or YAML file. If a directory, Retype will look for the `retype.[yml|yaml|json]` file in this directory.

```yaml
- uses: retypeapp/action-build@latest
  with:
    config_path: my_sub_directory/
```

## Outputs

### `RETYPE_OUTPUT_PATH`

Path to the Retype output location that can be referenced in other steps within the same workflow.

```sh
echo "${RETYPE_OUTPUT_PATH}"
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
      - uses: actions/checkout@v4

      - uses: retypeapp/action-build@latest
```

Here are a few common workflow scenarios.

### Minimum configuration for building a Retype project

```yaml
steps:
  - uses: retypeapp/action-build@latest
```

### Specify a Retype license key

If a license key is required, please configure using a GitHub Secret. See `RETYPE_SECRET` [documentation](https://retype.com/guides/github-actions/#retype_secret).

```yaml
- uses: retypeapp/action-build@latest
  with:
    secret: ${{ secrets.RETYPE_SECRET }}
```

For more information on how to set up and use secrets in GitHub actions, see [Encrypted secrets](https://docs.github.com/en/actions/reference/encrypted-secrets).

### Specify path to the retype.yml file

It is possible to point the directory where `retype.yml` is:

```yaml
- uses: retypeapp/action-build@latest
  with:
    config_path: my_docs
```

Or the full path (relative to the repository root) to retype.yml

```yaml
- uses: retypeapp/action-build@latest
  with:
    config_path: my_docs/retype.yml
```

The config file may have a different file name

```yaml
- uses: retypeapp/action-build@latest
  with:
    config_path: my_docs/retype-staging.json
```

In a bit more complex scenario where various repositories are checked out in a workflow. This may be useful, for instance, if retype documentation is generated from files across different repositories.

```yaml
- uses: actions/checkout@v4
  with:
    path: own-repository

- uses: actions/checkout@v4
  with:
    repository: organization/repository-name
    path: auxiliary-repository

- uses: retypeapp/action-build@latest
  with:
    config_path: own-repository/my_docs/retype.yml
```

### Passing the output path to another action

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

### Uploading the output as an artifact

To use the Retype output in another job within the same workflow, or let an external source download it, it is possible to use [`actions/upload-artifact`](https://github.com/actions/upload-artifact) to persist the files. The uploaded artifact can then be retrieved in another job or workflow using [`actions/download-artifact`](https://github.com/actions/download-artifact)

```yaml
- uses: retypeapp/action-build@latest
  id: build1

- uses: actions/upload-artifact@v2
  with:
    path: ${{ steps.build1.outputs.retype-output-path }}
```

### Publishing to GitHub Pages

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

### Build in `--strict` mode

Return a non-zero exit code if the build had errors or warnings. Set `true` to enable stict mode.

```yaml
- uses: retypeapp/action-build@latest
  with:
    strict: true
```

### Turn on `--verbose` logging

```yaml
- uses: retypeapp/action-build@latest
  with:
    verbose: true
```