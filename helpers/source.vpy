from vapoursynth import core


def get_attr(obj, attr, ex=False):
  try:
    s = obj
    for ns in attr.split("."):
      s = getattr(s, ns)
  except AttributeError as e:
    if ex: raise e
    return None
  return s


def get_source_filter(core):
  source_filter = get_attr(core, "lsmas.LWLibavSource")
  if source_filter:
    return source_filter

  source_filter = get_attr(core, "lsmas.LSMASHVideoSource")
  if source_filter:
    return source_filter

  source_filter = get_attr(core, "ffms2.Source")
  if source_filter:
    return source_filter

  raise Exception("No source filter found")


get_source_filter(core)(file).set_output()
