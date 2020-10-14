import vapoursynth, sys
core = vapoursynth.get_core()


def get_frames(s):
  video = core.lsmas.LWLibavSource(s)
  return video.num_frames


def get_keyframes(s):
  video = core.lsmas.LWLibavSource(s)
  frames = [
    i for i in range(video.num_frames)
    if video.get_frame(i).props._PictType.decode() == "I"
  ]
  return frames, video.num_frames
