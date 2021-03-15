# Retype APP Build Action

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