import vapoursynth, sys
core = vapoursynth.get_core()
video = core.ffms2.Source(sys.argv[1])
print(video.num_frames)
