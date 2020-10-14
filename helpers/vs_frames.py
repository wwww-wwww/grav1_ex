import vapoursynth, sys
core = vapoursynth.get_core()
video = core.lsmas.LWLibavSource(sys.argv[1])
print("frames: {}".format(video.num_frames))
