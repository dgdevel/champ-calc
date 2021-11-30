fs = require 'fs'

track_names = fs.readFileSync 'track-names.txt'
    .toString()
    .split '\n'
    .map (line) -> line.split ':'
    .map (pair) -> { search:pair[0], name:pair[1] }

exports.shorten = (name) ->
    for track_name in track_names
        if -1 isnt name.indexOf track_name.search
            return track_name.name
    return name
