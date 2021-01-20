import os, sys, subprocess, re

if hasattr(subprocess, "CREATE_NO_WINDOW"):
  CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW
else:
  CREATE_NO_WINDOW = 0


def get_aom_keyframes(path_ffmpeg, path_aomenc, path_in, scale_n, scale_d):
  ffmpeg = [
    path_ffmpeg,
    "-loglevel", "error",
    "-i", path_in,
    "-map", "0:v:0",
    "-vsync", "0",
    "-f", "yuv4mpegpipe", 
    "-vf", f"scale=iw*{scale_n}/{scale_d}:-1",
    "-"
  ]

  aom = [
    path_aomenc, "-",
    "--ivf", f"--fpf=fpf.log",
    f"--threads=8", "--passes=2",
    "--pass=1", "--auto-alt-ref=1",
    "--lag-in-frames=25",
    "-o", os.devnull
  ]

  try:
    ffmpeg_pipe = subprocess.Popen(
      ffmpeg,
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT,
      creationflags=CREATE_NO_WINDOW
    )

    pipe = subprocess.Popen(
      aom,
      stdin=ffmpeg_pipe.stdout,
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT,
      universal_newlines=True,
      creationflags=CREATE_NO_WINDOW
    )

    frame = -1
    while True:
      line = pipe.stdout.readline()

      if len(line) == 0 and pipe.poll() is not None:
        break

      match = re.search(r"frame.*?\/([^ ]+?) ", line.strip())
      if match:
        new_frame = int(match.group(1))
        if new_frame != frame:
          frame = new_frame
          print("frame", frame)

  finally:
    ffmpeg_pipe.kill()
    pipe.kill()

if __name__ == "__main__":
  if len(sys.argv) == 4:
    get_aom_keyframes(sys.argv[1], sys.argv[2], sys.argv[3], 1, 1.5)
