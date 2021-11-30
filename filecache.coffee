fs = require 'fs'

logger = require './logger'

class FileCache

  constructor: (filename) ->
    @filename = filename
    @content = {}

  put: (key, value, callback) ->
    @content[key] =
      value: value
      timestamp: Date.now()
    @store callback

  store: (callback) ->
    fileContent = JSON.stringify @content
    fs.writeFile @filename, fileContent, (err) =>
      if err
        throw err
      # logger.log "#{@filename} stored (#{fileContent.length} chars)"
      callback()

  get: (key, maxAge, callback) ->
    @load =>
      # logger.log key, maxAge, @content[key], @content[key].timestamp + maxAge, Date.now()
      if @content[key] and @content[key].timestamp + maxAge > Date.now()
        @content[key].timestamp = Date.now()
        callback yes, @content[key].value
      else
        callback no

  load: (callback) ->
    if Object.keys(@content).length
      callback()
    else
      fs.readFile @filename, (err, data) =>
        if not err
          @content = JSON.parse data
        callback()

exports.FileCache = FileCache

