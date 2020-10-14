import sys, enzyme
from enzyme.parsers import ebml
from enzyme.exceptions import MalformedMKVError
from datetime import timedelta

VIDEO_TRACK = 0x01
ignores = ["Void", "CRC-32"]


class MKV(object):
  def __init__(self, stream, recurse_seek_head=False):
    self.info = None
    self.video_tracks = []
    self.tags = []
    self.cues = []

    self.recurse_seek_head = recurse_seek_head
    self._parsed_positions = set()

    specs = ebml.get_matroska_specs()
    segments = ebml.parse(stream,
                          specs,
                          ignore_element_names=["EBML"],
                          max_level=0)
    if not segments:
      raise MalformedMKVError("No Segment found")
    segment = segments[0]

    stream.seek(segment.position)
    seek_head = ebml.parse_element(stream, specs)
    if seek_head.name != "SeekHead":
      raise MalformedMKVError("No SeekHead found")
    seek_head.load(stream, specs, ignore_element_names=ignores)
    self._parse_seekhead(seek_head, segment, stream, specs)

  def _parse_seekhead(self, seek_head, segment, stream, specs):
    for seek in seek_head:
      element_id = ebml.read_element_id(seek["SeekID"].data)
      element_name = specs[element_id][1]
      element_position = seek["SeekPosition"].data + segment.position

      if element_position in self._parsed_positions:
        continue

      if element_name == "Info":
        stream.seek(element_position)
        self.info = Info.fromelement(
          ebml.parse_element(stream, specs, True,
                             ignore_element_names=ignores))
      elif element_name == "Tracks":
        stream.seek(element_position)
        tracks = ebml.parse_element(stream,
                                    specs,
                                    True,
                                    ignore_element_names=ignores)
        self.video_tracks.extend([
          VideoTrack.fromelement(t) for t in tracks
          if t["TrackType"].data == VIDEO_TRACK
        ])
      elif element_name == "Tags":
        stream.seek(element_position)
        self.tags.extend([
          Tag.fromelement(t) for t in ebml.parse_element(
            stream, specs, True, ignore_element_names=ignores)
        ])
      elif element_name == "Cues":
        stream.seek(element_position)
        self.cues.extend([
          Cue.fromelement(t) for t in ebml.parse_element(
            stream, specs, True, ignore_element_names=ignores)
        ])
      elif element_name == "SeekHead" and self.recurse_seek_head:
        stream.seek(element_position)
        self._parse_seekhead(
          ebml.parse_element(stream, specs, True,
                             ignore_element_names=ignores), segment, stream,
          specs)

      self._parsed_positions.add(element_position)


class Info(object):
  def __init__(self, duration=None, timecode_scale=None):
    self.timecode_scale = timecode_scale
    self.duration = timedelta(microseconds=duration *
                              (timecode_scale or 1000000) //
                              1000) if duration else None

  @classmethod
  def fromelement(cls, element):
    duration = element.get("Duration")
    timecode_scale = element.get("TimecodeScale")
    return cls(duration, timecode_scale)


class Track(object):
  def __init__(self, type=None, number=None):
    self.type = type
    self.number = number

  @classmethod
  def fromelement(cls, element):
    type = element.get("TrackType")
    number = element.get("TrackNumber", 0)
    return cls(type=type, number=number)


class VideoTrack(Track):
  def __init__(self, **kwargs):
    super(VideoTrack, self).__init__(**kwargs)
    self.frame_duration = None

  @classmethod
  def fromelement(cls, element):
    videotrack = super(VideoTrack, cls).fromelement(element)
    videotrack.frame_duration = element.get("DefaultDuration")
    videotrack.uid = element.get("TrackUID")
    return videotrack


class Cue(object):
  def __init__(self, track, timestamp):
    self.track = track
    self.timestamp = timestamp

  @classmethod
  def fromelement(cls, element):
    if "CueTrackPositions" in element:
      track = element["CueTrackPositions"].get("CueTrack")
      timestamp = element.get("CueTime")
      return cls(track, timestamp)
    return cls(None, None)


class Tag(object):
  def __init__(self, targets=None, simpletags=None):
    self.targets = targets if targets is not None else []
    self.simpletags = simpletags if simpletags is not None else []

  @classmethod
  def fromelement(cls, element):
    targets = element["Targets"] if "Targets" in element else []
    simpletags = [
      SimpleTag.fromelement(s) for s in element if s.name == "SimpleTag"
    ]
    return cls(targets, simpletags)


class SimpleTag(object):
  def __init__(self,
               name,
               language="und",
               default=True,
               string=None,
               binary=None):
    self.name = name
    self.language = language
    self.default = default
    self.string = string
    self.binary = binary

  @classmethod
  def fromelement(cls, element):
    name = element.get("TagName")
    language = element.get("TagLanguage", "und")
    default = element.get("TagDefault", True)
    string = element.get("TagString")
    binary = element.get("TagBinary")
    return cls(name, language, default, string, binary)


def get_track_frames(mkv, track):
  for tag in mkv.tags:
    for target in tag.targets:
      if target.name == "TagTrackUID":
        if target.data == track:
          for st in tag.simpletags:
            if st.name.lower() == "number_of_frames":
              return int(st.string)

  return None


def get_keyframes(path):
  with open(path, "rb") as file:
    mkv = MKV(file)
    timecode_scale = mkv.info.timecode_scale

    video_track = mkv.video_tracks[0]

    uid = video_track.uid
    track_frames = get_track_frames(mkv, uid)

    track = video_track.number

    frame_duration = video_track.frame_duration

    timestamps = [cue.timestamp for cue in mkv.cues if cue.track == track]
    timestamps = [t - timestamps[0] for t in timestamps]

    frames = [round(timecode_scale / frame_duration * t) for t in timestamps]

    return frames, track_frames
