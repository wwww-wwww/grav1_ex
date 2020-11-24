import sys, subprocess, re

if hasattr(subprocess, "CREATE_NO_WINDOW"):
  CREATE_NO_WINDOW = subprocess.CREATE_NO_WINDOW
else:
  CREATE_NO_WINDOW = 0


def write_vs_script(src):
  src = src.replace("\\", "\\\\")
  script = f"""from vapoursynth import core
core.lsmas.LWLibavSource("{src}").set_output()"""

  open("vs.vpy", "w+").write(script)


def correct_split(path_vspipe, path_ffmpeg, path_in, path_out, start, length):
  write_vs_script(path_in)
  vspipe_cmd = [
    path_vspipe, "vs.vpy",
    "-s", str(start),
    "-e", str(start + length - 1),
    "-y", "-"
  ]
  
  ffmpeg_cmd = [
    path_ffmpeg, "-hide_banner",
    "-i", "-",
    "-c:v", "libx264",
    "-crf", "0",
    "-y", path_out
  ]

  pipe1 = subprocess.Popen(vspipe_cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    creationflags=CREATE_NO_WINDOW)

  pipe2 = subprocess.Popen(ffmpeg_cmd,
    stdin=pipe1.stdout,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    universal_newlines=True,
    creationflags=CREATE_NO_WINDOW)

  frame = -1
  while True:
    line = pipe2.stdout.readline().strip()

    if len(line) == 0 and pipe2.poll() is not None:
      break

    if not cb: continue
    matches = re.findall(r"frame= *([^ ]+?) ", line)
    if matches:
      new_frame = matches[-1]
      if new_frame != frame:
        print(f"frame {new_frame}")
        frame = new_frame

  pipe2.kill()
  pipe1.kill()

if len(sys.argv) > 1:
  correct_split(
    sys.argv[1],
    sys.argv[2],
    sys.argv[3],
    sys.argv[4],
    int(sys.argv[5]),
    int(sys.argv[6]))
