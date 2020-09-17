import subprocess, sys

if __name__ == "__main__":
  projectid = sys.argv[1]
  source = sys.argv[2]
  encoded = sys.argv[3]

  ffmpeg = [
    "ffmpeg", "-y",
    "-i", encoded,
    "-i", source,
    "-map", "0:v:0",
    "-map", "1:a:0",
    "-c:v", "copy",
    "-c:a", "copy",
    "{}.mkv".format(projectid)
  ]

  subprocess.run(ffmpeg, creationflags=subprocess.CREATE_NO_WINDOW)
