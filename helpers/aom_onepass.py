import sys, subprocess

if hasattr(subprocess, "CREATE_NO_WINDOW"):
  CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW
else:
  CREATE_NO_WINDOW = 0


def get_aom_keyframes(path_ffmpeg, path_onepass, path_in, scale_n, scale_d):
  ffmpeg = [
    path_ffmpeg,
    "-loglevel", "error",
    "-i", path_in,
    "-map", "0:v:0",
    "-vsync", "0",
    "-pix_fmt", "yuv420p",
    "-f", "yuv4mpegpipe",
    "-vf", f"scale=iw*{scale_n}/{scale_d}:-1",
    "-"
  ]

  try:
    ffmpeg_pipe = subprocess.Popen(ffmpeg,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      creationflags=CREATE_NO_WINDOW)

    pipe = subprocess.Popen([path_onepass],
      stdin=ffmpeg_pipe.stdout,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      universal_newlines=True,
      creationflags=CREATE_NO_WINDOW)

    while True:
      line = pipe.stderr.readline()

      if len(line) == 0 and pipe.poll() is not None:
        break

      print(line.strip())

  finally:
    ffmpeg_pipe.kill()
    pipe.kill()

if __name__ == "__main__":
  if len(sys.argv) == 4:
    get_aom_keyframes(sys.argv[1], sys.argv[2], sys.argv[3], 1, 1.5)
