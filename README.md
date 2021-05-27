# Grav1
## Distributed encoding management server

![projects page](https://user-images.githubusercontent.com/19401176/102001907-ff959780-3cab-11eb-9597-8254bc809f5e.png)

|||
|-|-|
|![clients page](https://user-images.githubusercontent.com/19401176/103187415-17a71280-4879-11eb-9b03-9014f9a45df5.png)|![adding projects](https://user-images.githubusercontent.com/19401176/103187418-183fa900-4879-11eb-89d5-e9a54cd2695c.png)|

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
- [mkvmerge & mkvextract v50.0.0.43+](https://mkvtoolnix.download/downloads.html) (optional)
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

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser

## Initial setup:

 * Sign up at [`localhost:4000/sign_up`](http://localhost:4000/sign_up)
 * Grant yourself permissions by entering `Grav1.Repo.get(Grav1.User, "USERNAME") |> Grav1.User.set_level(100)` into the interactive shell

Now you can add projects at [`localhost:4000/projects`](http://localhost:4000/projects)

## Managing users:
  Upgrading to argon2 will break users' passwords.  
  Simply delete the user using `Grav1.Repo.get(Grav1.User, "USERNAME") |> Grav1.Repo.delete()`

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).
