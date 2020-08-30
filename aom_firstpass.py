import os, sys, subprocess, re

def get_aom_keyframes(src):
  ffmpeg = ["ffmpeg", "-y",
    "-hide_banner",
    "-loglevel", "error",
    "-i", src,
    "-map", "0:v:0",
    "-strict", "-1",
    "-pix_fmt", "yuv420p",
    "-vsync", "0",
    "-f", "yuv4mpegpipe", "-"]

  aom = ["aomenc", "-",
    "--ivf", f"--fpf=fpf.log",
    f"--threads=8", "--passes=2",
    "--pass=1", "--auto-alt-ref=1",
    "--lag-in-frames=25",
    "-o", os.devnull]

  aom.extend(["-w", "1280", "-h", "720"])

  if True:
    ffmpeg_pipe = subprocess.Popen(ffmpeg,
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT,
      creationflags=subprocess.CREATE_NO_WINDOW)

    pipe = subprocess.Popen(aom,
      stdin=ffmpeg_pipe.stdout,
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT,
      universal_newlines=True,
      creationflags=subprocess.CREATE_NO_WINDOW)

    frame = -1
    while True:
      line = pipe.stdout.readline().strip()

      if len(line) == 0 and pipe.poll() is not None:
        break

      match = re.search(r"frame.*?\/([^ ]+?) ", line)
      if match:
        new_frame = int(match.group(1))
        if new_frame != frame:
          frame = new_frame
          sys.stdout.write(f"frame {frame}\n")

if len(sys.argv) > 1:
  get_aom_keyframes(sys.argv[1])
