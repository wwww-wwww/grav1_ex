[
  import_deps: [:ecto, :phoenix],
  inputs:
    Enum.flat_map(
      ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{ex,exs}"],
      &Path.wildcard(&1, match_dot: true)
    ) --
      ["lib/grav1/encoder.ex"],
  subdirectories: ["priv/*/migrations"]
]
