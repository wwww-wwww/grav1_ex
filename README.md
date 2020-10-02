# Grav1
## Distributed encoding management server

Client is located [here](https://github.com/wwww-wwww/grav1_ex_client)

### Requirements

- elixir ~> 1.7 (Erlang/OTP ~> 21)
- postgres
- nodejs

### External dependencies

- ffmpeg
- [aomenc](https://aomedia.googlesource.com/aom/)
- [dav1d](https://code.videolan.org/videolan/dav1d)
- python 3.6+
- [vapoursynth](https://github.com/vapoursynth/vapoursynth/releases) and vspipe (optional)
- [mkvmerge v50.0.0.43+](https://mkvtoolnix.download/downloads.html) (optional)
- [onepass_keyframes](https://gist.github.com/wwww-wwww/aeed66e165fe60cbbb7fed2827ad912e) [binaries](https://bin.grass.moe/onepass_keyframes/) example program (optional)

### Python dependencies
Not required but will significantly decrease the time taken to split.
```
enzyme
vapoursynth
```

## To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Install Node.js dependencies with `npm install` inside the `assets` directory
  * Start Phoenix endpoint with `mix phx.server`
    * Or enter the interactive shell with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).
