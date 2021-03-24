# Retype APP GitHub Actions (RAGHA) - Build

GitHub action to Build retype applications. After the action completes it will export the `retype-output-root` value for the next step to handle the built files. The output directory will point to a folder containing **retype.json** file and **output/** folder with actual built documentation website.

The action will look for **retype.json** file at repository root. If it is found, then it is used, overriding the `input` and `output` parameters, and optionally `base` and `title` (read below).

If the **retype.json** file is not found, then a new file will be generated via `retype init` and its `input` and `output` values adjusted.
## Simple example using recommended dependencies:

```yaml
steps:
- uses: actions/checkout@v2

- uses: actions/setup-dotnet@v1
  with:
    dotnet-version: 5.0.x

- uses: retypeapp/action-build
```

Adding the **setup-dotnet** action will ensure .NET 5 is available, so the action will choose the smaller **dotnet tool** retype installation instead of the NPM one. The NPM version is larger in size because it carries on .NET dependencies cross-platform.

## Specify a custom base directory

In case the target hosting will not be in the website's root, the path to documentation must be explicitly specified. For convenience, the action can override the `base` setting in **retype.json** to the desired value if it can't be committed to the config file (or when using default config).

```yaml
steps:
- uses: actions/checkout@v2

- uses: actions/setup-dotnet@v1
  with:
    dotnet-version: 5.0.x

- name: Set clean repository name (without owner name)
  id: clean-repo-name
  shell: bash
  run: echo "::set-output name=repository_name::${GITHUB_REPOSITORY#${{ github.repository_owner }}/}"

- uses: retypeapp/action-build
  with:
    base: "${{ steps.clean-repo-name.outputs.repository_name }}"
```

The example above is useful to set up GitHub pages using the **_repo-owner_.github.io/_repo-name_** path for hosting documentation built by retype.

## Specify a custom project name

The `title` setting in **retype.json** can be overridden with the `project-name` action input.

```yaml
steps:
- uses: actions/checkout@v2

- uses: actions/setup-dotnet@v1
  with:
    dotnet-version: 5.0.x

- uses: retypeapp/action-build
  with:
    project-name: "My Project"
```

While this may help get started with documentation when there's no **retype.json** file in the repository's root, it's best to define the project name in the config file (`title` setting).

## Using the output path in a custom action

It is possible to get the output path of the built Retype documentation website to use with custom steps/actions after **retype build** action is done. To do so, use the action's `retype-output-root` **output** value.

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

      - uses: retypeapp/action-build
        id: build1

      - shell: bash
        env:
          RETYPE_BUILD_PATH: ${{ steps.build1.outputs.retype-output-root }}
        run: echo "Retype config is at '${RETYPE_BUILT_PATH}' and the actual output at '${RETYPE_BUILT_PATH}'."
```

Other retype actions internally rely on the `RETYPE_OUTPUT_ROOT` environment variable exported by this action, but to ensure your action will work with future versions, it is safer to reference the explicit output value.

**Notice:** If the custom action runs on another job, it is needed to actually upload the built documentation with the **upload-artifact** action, as changes in the file system are not available across different GitHub actions' jobs. Then from the outside job, the artifact can be retrieved using the **download-artifact** action. See examples using the action below; more information on the **upload-artifact** and **download-artifact** actions available at, respectively, https://github.com/actions/upload-artifact and https://github.com/actions/download-artifact.

## Uploading retype built website as an artifact

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

      - uses: retypeapp/action-build
        id: build1

      - uses: actions/upload-artifact@v2
        with:
          path: ${{ steps.build1.outputs.retype-output-root }}
```

For more information on upload artifact, see https://github.com/actions/upload-artifact.