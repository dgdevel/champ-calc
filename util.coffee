buffer = require 'buffer'

exports.sum = (a) -> a.reduce (a,b) -> a + b

listexec = exports.listexec = (list, fn, callback, results=[]) ->
  if list.length is 0
    return callback results
  elem = list[0]
  tail = list.slice(1)
  fn elem, (result) ->
    results.push result
    if tail.length is 0
      callback results
    else
      listexec tail, fn, callback, results

exports.asc = (a, b) -> a - b

exports.desc = (a, b) -> b - a

exports.sort = (a, fn) ->
  a = JSON.parse JSON.stringify a
  a.sort(fn)

exports.clone = (o) -> JSON.parse JSON.stringify o

exports.unescape_plus = (s) -> unescape s.replace(/\+/g, '%20')

exports.fix_names = (name) ->
  b = buffer.transcode Buffer.from(name), "utf8", "latin1"
  b.toString 'utf8'

