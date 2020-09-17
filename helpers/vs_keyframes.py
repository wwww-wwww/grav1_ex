import vapoursynth, sys
core = vapoursynth.get_core()
video = core.ffms2.Source(sys.argv[1])
frames = [str(i) for i in range(video.num_frames) if video.get_frame(i).props._PictType.decode() == "I"]
print(",".join(frames))
print("total_frames:", video.num_frames)
