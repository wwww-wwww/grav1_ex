import os, sys, subprocess, re

if hasattr(subprocess, "CREATE_NO_WINDOW"):
  CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW
else:
  CREATE_NO_WINDOW = 0


def get_aom_keyframes(ffmpeg_path, aomenc_path, src, width, height):
  ffmpeg = [
    ffmpeg_path,
    "-loglevel", "error",
    "-i", src,
    "-map", "0:v:0",
    "-vsync", "0",
    "-f", "yuv4mpegpipe", "-"
  ]

  aom = [
    aomenc_path, "-",
    "--ivf", f"--fpf=fpf.log",
    f"--threads=8", "--passes=2",
    "--pass=1", "--auto-alt-ref=1",
    "--lag-in-frames=25",
    "-o", os.devnull
  ]

  if width > 0 and height > 0:
    aom.extend(["-w", str(width), "-h", str(height)])

  ffmpeg_pipe = subprocess.Popen(ffmpeg,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    creationflags=CREATE_NO_WINDOW)

  pipe = subprocess.Popen(aom,
    stdin=ffmpeg_pipe.stdout,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    universal_newlines=True,
    creationflags=CREATE_NO_WINDOW)

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
        print("frame", frame)

  ffmpeg_pipe.kill()
  pipe.kill()

if __name__ == "__main__":
  if len(sys.argv) == 4:
    get_aom_keyframes(
      sys.argv[1],
      sys.argv[2],
      sys.argv[3],
      1280, 720)
