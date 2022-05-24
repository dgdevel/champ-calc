
fs = require 'fs'
path = require 'path'
ir = require './ir'
logger = require './logger'
util = require './util'
filecache = require './filecache'

credentials = JSON.parse fs.readFileSync 'credentials.json'

cache = new filecache.FileCache('iratings.cache')

subsessionids = fs.readFileSync process.argv[2]
    .toString()
    .split '\n'
    .filter (line) -> line isnt ''
    .map (line) -> line.match /subsessionid=([0-9]+)/
    .map (match) -> parseInt match[1], 10

unescape_plus = util.unescape_plus
clone = util.clone
fix_names = util.fix_names

process_session = (subsessionid, callback) ->
  ir.get_subsession_results subsessionid, (result) ->
    end_time = null
    res =
      subsessionid: subsessionid
      start_time : unescape_plus result.start_time
      track_name: unescape_plus "#{result.track_name}"
      rows : result.rows.filter((row) -> row.simsesname is 'RACE').map (row) ->
        return
          name : unescape_plus row.displayname
          custid: row.custid
          incidents: row.incidents
          laps: row.lapscomplete
          end_time: row.subsessionfinishedat
    res.end_time = end_time
    util.listexec res.rows, get_irating_for_row, (rows) ->
      callback res

get_irating_for_row = (row, callback) ->
  key = "irating.#{row.custid}.#{row.end_time}"
  cache.get key, (365 * 24 * 60 * 60 * 1000), (found, value) ->
    if found
      # logger.log 'get_irating_for_row (cached)', value.irating, value.source, value.detail, value.date
      row.irating = value.irating
      callback row
    else
      ir.get_irating_at_time row.custid, 2, row.end_time, (irating, source, detail, date) ->
        # logger.log 'get_irating_for_row',row.name, irating, source, detail, new Date(date), new Date(row.end_time)
        cache.put key,
          irating: irating
          source: source
          detail: detail
          date: date
        , ->
          row.irating = irating
          callback row

sort_fn = (a,b) ->
  if a.laps is b.laps
    b.irating - a.irating
  else
    b.laps - a.laps

process_results = (results) ->
  for r in results
    console.log r.track_name
    for d in r.rows.sort sort_fn
      console.log d.irating, '\t', d.incidents, '\t', d.laps, '\t', d.name

ir.login credentials.username, credentials.password, (loggedIn) ->
  if not loggedIn
    return console.error 'not logged in'
  util.listexec subsessionids, process_session, process_results


