defmodule Mix.Tasks.RodarBpmn.Release do
  @shortdoc "Creates a release by updating VERSION, CHANGELOG, and tagging"

  @moduledoc """
  Creates a release by stripping the `-dev` suffix from the current version,
  updating the CHANGELOG, committing, tagging, and bumping to the next dev version.

  ## Usage

      mix rodar_bpmn.release <bump>

  where `<bump>` is one of `patch`, `minor`, or `major`.

  The current version (from the `VERSION` file) must end with `-dev`. The `-dev`
  suffix is stripped to produce the release version. After tagging, the version is
  bumped according to the specified segment and `-dev` is appended.

  For example, if the current version is `0.1.0-dev`:

    * `mix rodar_bpmn.release patch` - releases 0.1.0, then bumps to 0.1.1-dev
    * `mix rodar_bpmn.release minor` - releases 0.1.0, then bumps to 0.2.0-dev
    * `mix rodar_bpmn.release major` - releases 0.1.0, then bumps to 1.0.0-dev

  ## Options

    * `--dry-run` - show what would happen without making any changes
    * `--publish` - publish the package to Hex after tagging the release

  ## Prerequisites

  The git working directory must be clean (no uncommitted changes).
  """

  use Mix.Task

  @version_file "VERSION"
  @changelog_file "CHANGELOG.md"

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args, strict: [dry_run: :boolean, publish: :boolean])

    dry_run = Keyword.get(opts, :dry_run, false)
    publish = Keyword.get(opts, :publish, false)

    bump =
      case positional do
        [b] when b in ~w(patch minor major) ->
          String.to_atom(b)

        _ ->
          Mix.raise("Usage: mix rodar_bpmn.release <patch|minor|major> [--dry-run] [--publish]")
      end

    current_version = read_version()
    validate_dev_suffix!(current_version)

    unless dry_run do
      validate_clean_working_tree!()
    end

    release_version = String.replace_suffix(current_version, "-dev", "")
    next_dev_version = bump_version(release_version, bump) <> "-dev"
    today = Date.utc_today() |> Date.to_iso8601()

    Mix.shell().info("Release plan:")
    Mix.shell().info("  Current version:  #{current_version}")
    Mix.shell().info("  Release version:  #{release_version}")
    Mix.shell().info("  Next dev version: #{next_dev_version}")
    Mix.shell().info("  Bump type:        #{bump}")
    Mix.shell().info("")

    if dry_run do
      Mix.shell().info("[dry-run] Would update VERSION to #{release_version}")
      Mix.shell().info("[dry-run] Would update CHANGELOG.md with release date #{today}")
      Mix.shell().info("[dry-run] Would commit: release: v#{release_version}")
      Mix.shell().info("[dry-run] Would tag: v#{release_version}")

      if publish do
        Mix.shell().info("[dry-run] Would publish to Hex")
      end

      Mix.shell().info("[dry-run] Would update VERSION to #{next_dev_version}")
      Mix.shell().info("[dry-run] Would commit: build: start v#{next_dev_version} development")
    else
      step("Updating VERSION to #{release_version}", fn ->
        write_version(release_version)
      end)

      step("Updating CHANGELOG.md with release date", fn ->
        update_changelog(release_version, today)
      end)

      step("Committing release v#{release_version}", fn ->
        git!(["add", @version_file, @changelog_file])
        git!(["commit", "-m", "release: v#{release_version}"])
      end)

      step("Tagging v#{release_version}", fn ->
        git!(["tag", "-a", "v#{release_version}", "-m", "Release v#{release_version}"])
      end)

      if publish do
        step("Publishing v#{release_version} to Hex", fn ->
          mix!(["hex.publish", "--yes"])
        end)
      end

      step("Bumping VERSION to #{next_dev_version}", fn ->
        write_version(next_dev_version)
      end)

      step("Committing next dev version", fn ->
        git!(["add", @version_file])
        git!(["commit", "-m", "build: start v#{next_dev_version} development"])
      end)

      Mix.shell().info("")
      Mix.shell().info("Release v#{release_version} complete!")
      Mix.shell().info("")
      Mix.shell().info("Next steps:")
      Mix.shell().info("  git push origin main --tags")
      Mix.shell().info("  # then merge main back into develop")
    end
  end

  defp read_version do
    case File.read(@version_file) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> Mix.raise("Could not read #{@version_file}")
    end
  end

  defp write_version(version) do
    File.write!(@version_file, version <> "\n")
  end

  defp validate_dev_suffix!(version) do
    unless String.ends_with?(version, "-dev") do
      Mix.raise(
        "Current version #{version} does not have a -dev suffix. " <>
          "Can only release from a development version."
      )
    end
  end

  defp validate_clean_working_tree! do
    {output, 0} = System.cmd("git", ["status", "--porcelain"])

    unless output == "" do
      Mix.raise(
        "Working directory is not clean. " <>
          "Please commit or stash your changes before releasing."
      )
    end
  end

  defp bump_version(version, bump) do
    [major, minor, patch] =
      version
      |> String.split(".")
      |> Enum.map(&String.to_integer/1)

    case bump do
      :patch -> "#{major}.#{minor}.#{patch + 1}"
      :minor -> "#{major}.#{minor + 1}.0"
      :major -> "#{major + 1}.0.0"
    end
  end

  defp update_changelog(version, date) do
    content = File.read!(@changelog_file)

    updated =
      String.replace(
        content,
        "## [Unreleased]",
        "## [Unreleased]\n\n## [#{version}] - #{date}",
        global: false
      )

    File.write!(@changelog_file, updated)
  end

  defp mix!(args) do
    case System.cmd("mix", args, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, code} ->
        Mix.raise("mix #{Enum.join(args, " ")} failed (exit #{code}):\n#{output}")
    end
  end

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, code} ->
        Mix.raise("git #{Enum.join(args, " ")} failed (exit #{code}):\n#{output}")
    end
  end

  defp step(description, fun) do
    Mix.shell().info("=> #{description}")
    fun.()
  end
end
