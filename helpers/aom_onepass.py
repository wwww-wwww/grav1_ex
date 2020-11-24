import os, sys, subprocess, re

if hasattr(subprocess, "CREATE_NO_WINDOW"):
  CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW
else:
  CREATE_NO_WINDOW = 0


def get_aom_keyframes(ffmpeg_path, onepass_path, src, width, height):
  ffmpeg = [
    ffmpeg_path,
    "-loglevel", "error",
    "-i", src,
    "-map", "0:v:0",
    "-vsync", "0",
    "-pix_fmt", "yuv420p",
    "-f", "yuv4mpegpipe"
  ]

  if width > 0 and height > 0:
    ffmpeg.extend(["-vf", f"scale={width}:{height}"])

  ffmpeg.append("-")

  ffmpeg_pipe = subprocess.Popen(ffmpeg,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    creationflags=CREATE_NO_WINDOW)

  pipe = subprocess.Popen([onepass_path],
    stdin=ffmpeg_pipe.stdout,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    creationflags=CREATE_NO_WINDOW)

  frame = -1
  while True:
    line = pipe.stderr.readline().strip()

    if len(line) == 0 and pipe.poll() is not None:
      break

    print(line.decode("utf-8"))
    
  ffmpeg_pipe.kill()
  pipe.kill()

if __name__ == "__main__":
  if len(sys.argv) == 4:
    get_aom_keyframes(
      sys.argv[1],
      sys.argv[2],
      sys.argv[3],
      1280, 720)
