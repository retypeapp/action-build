# Retype APP GitHub Actions - Build

A GitHub Action to build a [Retype](https://retype.com/) powered website. The output of this action is then made available for subsequent workflow steps, such as publishing to GitHub Pages using the [retypeapp/action-github-pages](https://github.com/retypeapp/action-github-pages) action.

The output of this step can be published to any website hosting service.

## Introduction

This action runs `retype build` over the repository to build a website in the form of a static web site that can be published to any website hosting solution available.

After the action completes, it will export the `retype-output-root` value for the next steps to handle the output. These output files can then be pushed back to GitHub (for GitHub Pages hosted websites), or sent by FTP to another web server, or any other form of website publication target.

This action will look for a [`retype.json`](https://retype.com/configuration/project/) file in the repository root.

## Prerequisites

We highly recommend configuring the [actions/setup-dotnet](https://github.com/actions/setup-dotnet) step before `retypeapp/action-build`. This will install the tiny `dotnet` Retype package instead of the larger self-contained NPM package. Both the `dotnet` and `npm` packages run the exact same version of Retype, it's just the size of the `dotnet` package is much smaller, so the action will setup faster.

## Usage

```yaml
steps:
- uses: actions/checkout@v2

- uses: actions/setup-dotnet@v1
  with:
    dotnet-version: 5.0.x

- uses: retypeapp/action-build
```

## Inputs

### `base`

The [`base`](https://retype.com/configuration/project#base) subfolder path appended to URL.

- **Default:** null

The `base` is required if the target host will prefix a path to your website, such as the repository name with GitHub Pages hosting. For instance, https://example.com/docs/ would require `base: docs` to be configured. The path https://example.com/en/ would require `base: en` to be configured.

The `base` can also be set in the project `retype.json` file.

### `license`

Specifies the license key to be used with Retype.

**WARNING**: Never save the `license` key value to your `retype.yaml` or `retype.json` files. Use a GitHub Secret to store the value. For information on how to set up secrets, see [Encrypted Secrets](https://docs.github.com/en/actions/reference/encrypted-secrets).

### `title`

Specifies a given title to be used for the generated website.

Passing the `title` value will override the `identity.title` value provided in the `retype.json` or the default value used by Retype in cases where no `retype.json` is available.

## Examples

Here are some simple and common workflow scenarios. For most of the examples below, the following `retype.yaml` workflow file will serve as our starting template.

```yaml
name: document
on: push
jobs:
  job1:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - uses: actions/setup-dotnet@v1
        with:
          dotnet-version: 5.0.x
```

### Basic scenario using recommended dependencies:

```yaml
steps:
- uses: retypeapp/action-build
```

## Specify a custom `base` directory

If the output is not hosted from the website root folder, a `base` needs to be explicitly configured.

The `base` would typically be configured in the `retype.json` file.

```yaml
- name: Sets a variable with the repository name, stripping out owner/organization
  id: clean-repo-name
  shell: bash
  run: echo "::set-output name=repository_name::${GITHUB_REPOSITORY#${{ github.repository_owner }}/}"

- uses: retypeapp/action-build
  with:
    base: "${{ steps.clean-repo-name.outputs.repository_name }}"
```

The example above is useful to set up GitHub Pages using the `repo-owner.github.io/repo-name` path for hosting documentation built by Retype. For more information, see [Working with GitHub Pages](https://docs.github.com/en/github/working-with-github-pages).

## Specify a custom documentation website title

The `title` setting in `retype.json` can be overridden with the `title` action input.

```yaml
- uses: retypeapp/action-build
  with:
    title: "My Project"
```

While this may help get started when no `retype.json` file is available, it is best to define the project name in the projects `retype.json` file within `identity.title` setting. See [Project configuration](https://retype.com/configuration/project/) for more details.

## Specify Retype license key

If a `license` is required, please configure using a GitHub secret.

```yaml
- uses: retypeapp/action-build
  with:
    license: ${{ secrets.RETYPE_LICENSE_KEY }}
```

For more information on how to set up and use secrets in GitHub actions, see [Encrypted secrets](https://docs.github.com/en/actions/reference/encrypted-secrets).

## Using the output path in a custom action

It is possible to get the output path of the built Retype documentation website to use with custom steps/actions after the `action-build` is complete. To do so, use the `retype-output-root` value.

```yaml
- uses: retypeapp/action-build
  id: build1

- shell: bash
  env:
    RETYPE_BUILD_PATH: ${{ steps.build1.outputs.retype-output-root }}
  run: echo "Retype config is at '${RETYPE_BUILT_PATH}' and the actual output at '${RETYPE_BUILT_PATH}'."
```

Other Retype actions within the workflow may rely on the output of this action by using the `RETYPE_OUTPUT_ROOT` environment variable, but to ensure your action will work with future versions, it is safer to reference the explicit output value.

If the custom action runs on another job, see the next example for means to persist the built documentation website.

It is required to actually upload the built documentation with [actions/upload-artifact](https://github.com/actions/upload-artifact), as changes in the file system are not available across different GitHub action jobs. Then from the outside job, the artifact can be retrieved using the `download-artifact` action. See examples using the action below; more information on the [`upload-artifact`](https://github.com/actions/upload-artifact) and [`download-artifact`](https://github.com/actions/download-artifact) actions.

## Uploading a Retype built website as an artifact

To use the Retype output in another job within the same workflow, or let an external source download it, it is possible to use [`actions/upload-artifact`](https://github.com/actions/upload-artifact) to persist the files. The uploaded artifact can then be retrieved in another job or workflow using [`actions/download-artifact`](https://github.com/actions/download-artifact)

```yaml
- uses: retypeapp/action-build
  id: build1

- uses: actions/upload-artifact@v2
  with:
    path: ${{ steps.build1.outputs.retype-output-root }}
```

## Pushing back to GitHub Pages

By using the Retype [retypeapp/action-github-pages](https://github.com/retypeapp/action-github-pages) action, the workflow can publish the freshly built website to a `branch` or `directory` or even a make a Pull Request. The website can then be hosted using [GitHub Pages](https://docs.github.com/en/github/working-with-github-pages/getting-started-with-github-pages).

The snippet below illustrates how to add GitHub Pages publishing support to a Retype Build workflow:

```yaml
- uses: retypeapp/action-build

- uses: retypeapp/action-github-pages
  with:
    branch: retype
    update-branch: true
```
