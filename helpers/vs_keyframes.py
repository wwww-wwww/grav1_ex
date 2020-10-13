import vapoursynth, sys
core = vapoursynth.get_core()
video = core.lsmas.LWLibavSource(sys.argv[1])
frames = [str(i) for i in range(video.num_frames) if video.get_frame(i).props._PictType.decode() == "I"]
print(",".join(frames))
print("total frames:", video.num_frames)
