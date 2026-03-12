# Building and Testing

This document describes how to set up your development environment to build and test Rodar Workflow.

* [Prerequisite Software](#prerequisite-software)
* [Getting the Sources](#getting-the-sources)
* [Installing HEX Modules](#installing-hex-modules)
* [Building](#building)
* [Building Documentation Locally](#building-documentation-locally)
* [Running Tests Locally](#running-tests-locally)

See the [contribution guidelines](CONTRIBUTING.md) if you'd like to contribute to Rodar Workflow.

## Prerequisite Software

Before you can build and test Rodar Workflow, you must install and configure the
following products on your development machine:

* [Git](http://git-scm.com) and/or the **GitHub app** (for [Mac](http://mac.github.com) or
  [Windows](http://windows.github.com)); [GitHub's Guide to Installing
  Git](https://help.github.com/articles/set-up-git) is a good source of information.

* [Elixir](https://elixir-lang.org) (~> 1.16) with OTP 27+, which is used to run the code and tests.

## Getting the Sources

Fork and clone the Rodar Workflow repository:

1. Login to your GitHub account or create one by following the instructions given
   [here](https://github.com/signup/free).
2. [Fork](http://help.github.com/forking) the [main Rodar Workflow
   repository](https://github.com/rodar-project/rodar).
3. Clone your fork of the repository and define an `upstream` remote pointing back to
   the repository that you forked in the first place.

```shell
# Clone your GitHub repository:
git clone git@github.com:<github username>/rodar.git

# Go to the rodar directory:
cd rodar

# Add the main repository as an upstream remote to your repository:
git remote add upstream https://github.com/rodar-project/rodar.git
```

## Installing HEX packages

Next, install the Hex packages needed to build and test Rodar Workflow:

```shell
mix local.hex --force
mix local.rebar --force
mix deps.get
mix deps.compile
mix compile
```

## Building

To build Rodar Workflow for release run:

```shell
mix deps.get --only prod
mix deps.compile
mix release --warnings-as-errors --env=prod
```

* Results are put in the lib folder.

## Building Documentation Locally

To generate the documentation:

```shell
mix docs
```

## Running Tests Locally

To run the full verification suite:

```shell
mix compile --warnings-as-errors  # Compile with strict warnings
mix test                          # Run all tests
mix credo                         # Lint
mix dialyzer                      # Static type analysis
mix coveralls                     # Tests with coverage report
```

You should execute the test suites before submitting a PR to GitHub.

All tests are executed on our Continuous Integration infrastructure (GitHub Actions) and a PR can only be merged once all checks pass.
