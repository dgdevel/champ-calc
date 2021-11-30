

exports.log = ->
  args = [ "[" + new Date().toISOString().substring(11,23) + "]" ]
  for arg in arguments
    args.push arg
  console.log.apply console, args

