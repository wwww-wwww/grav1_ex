import os, logging, time, requests
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

directory = os.path.dirname(os.path.realpath(__file__))
exts = [".mkv"]
api_key = "jtZLGswI0OV8AoEiZfCQItVwSz9XBu52"
endpoint = "http://localhost:4000/api/add_project"

params = {
  "encoder": "aomenc",
  "priority": -100,
  "split_min_frames": 24,
  "split_max_frames": 192,
  "encoder_params": [
    "--lag-in-frames=35",
    "-b", "8",
    "--cpu-used=3",
    "--end-usage=q",
    "--cq-level=24",
    "-w", "1920",
    "-h", "1080",
    "--tile-columns=1",
    "--enable-keyframe-filtering=0",
  ],
  "ffmpeg_params": [],
  "on_complete": "actions/merge.py",
  "start_after_split": True,
  "copy_timestamps": True
}

session = requests.Session()


def proc(path):
  if os.path.splitext(path)[1].lower() not in exts: return
  while True:
    try:
      open(path).close()
      break
    except:
      time.sleep(1)

  body = {"files": [path], "params": params, "key": api_key}

  with session.post(endpoint, json=body) as r:
    print(r.json())


class Monitor(FileSystemEventHandler):
  def __init__(self, directory):
    self.observer = Observer()
    self.observer.schedule(self, directory, recursive=True)
    self.observer.start()
    logging.info(f"Started monitoring {directory}")

  def dispose(self):
    self.observer.stop()

  def on_moved(self, evt):
    if not os.path.isfile(evt.dest_path): return
    logging.info("File moved: {}".format(evt.dest_path))
    proc(evt.dest_path)

  def on_created(self, evt):
    if not os.path.isfile(evt.src_path): return
    logging.info("File created: {}".format(evt.src_path))
    proc(evt.src_path)


if __name__ == "__main__":
  logging.basicConfig(level=logging.INFO)
  monitor = Monitor(directory)
  print("q + return or Ctrl + C to quit")

  try:
    while input().lower() != "q":
      pass
  except KeyboardInterrupt:
    pass

  monitor.dispose()
