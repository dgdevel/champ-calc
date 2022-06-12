
fs = require 'fs'
path = require 'path'
ir = require './ir'
logger = require './logger'
util = require './util'
filecache = require './filecache'
track_names = require './track-names'

S5PointsStandingsManager = (require './s5points').S5PointsStandingsManager

manager = new S5PointsStandingsManager


ExcelJS = require 'exceljs'

credentials = JSON.parse fs.readFileSync 'credentials.json'

cache = new filecache.FileCache('results.cache')

subsessionids = fs.readFileSync process.argv[2]
    .toString()
    .split '\n'
    .filter (line) -> line isnt ''
    .map (line) -> line.match /subsessionid=([0-9]+)/
    .map (match) -> parseInt match[1], 10

unescape_plus = util.unescape_plus
clone = util.clone
fix_names = util.fix_names

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

    # fix per nomi dei circuiti lunghi
    res.track_name = track_names.shorten res.track_name

    res.end_time = end_time
    res.rows_pts = res.rows
    util.listexec res.rows_pts, get_irating_for_row, (rows) ->
      res.rows_pts = rows
      res.standings = manager.add_race rows
      callback res

tab = '\t'

incs_sort = (a,b) ->
  if a.incs_races < 8 and b.incs_races < 8 and a.incs_races isnt b.incs_races
    b.incs_races - a.incs_races
  else if a.incs_races < 8 and b.incs_races >= 8
    1
  else if a.incs_races >= 8 and b.incs_races < 8
    -1
  else
    util.sum(util.sort(a.incs, util.asc).slice(0,8)) - util.sum(util.sort(b.incs, util.asc).slice(0,8))

excel_addsheet = (workbook, name, color, headers, rows) ->
  sheet = workbook.addWorksheet name,
    properties:
      tabColor:
        argb: color
  sheet.columns = ({ header: k, width: v } for k,v of headers)
  for row, i in rows
    for cell, j in row
      sheet.getRow(i+2).getCell(j+1).value = cell
  sheet

process_results = (results) ->
  drivers_lookup = {}
  for result in results
    for row in result.rows
      if not drivers_lookup[row.custid]
        drivers_lookup[row.custid] = fix_names row.name
  # excel output
  workbook = new ExcelJS.Workbook()
  workbook.creator = 'dgdevel'
  excel_addsheet workbook, 'Overall', 'FFFF0000',
    Pilota : 50
    Punti: 8
    'Gare Disputate': 15
    Variazione: 12
    'Dettaglio': 80
  , results.slice(-1)[0].standings.standings.overall.map (entry) -> [
    drivers_lookup[entry.custid]
    if entry.points > 0 then entry.points else ''
    entry.race_completed
    if entry.variation > 0 then "+#{entry.variation}" else if entry.variation < 0 then "#{entry.variation}" else "-"
    entry.results.join ', '
  ]
  excel_addsheet workbook, 'AM', 'FFFF0000',
    Pilota : 50
    Punti: 8
    'Gare Disputate': 15
    Variazione: 12
    'Dettaglio': 80
  , results.slice(-1)[0].standings.standings.am.map (entry) -> [
    drivers_lookup[entry.custid]
    if entry.points > 0 then entry.points else ''
    entry.race_completed
    if entry.variation > 0 then "+#{entry.variation}" else if entry.variation < 0 then "#{entry.variation}" else "-"
    entry.results.join ', '
  ]
  for result in results
    rows = []
    if result.standings.official
      rows = result.standings.race.overall.map (entry) ->
        name = drivers_lookup[entry.custid]
        overall = entry.points
        am = result.standings.race.am.filter (e) -> e.custid is entry.custid
        laps = result.rows.filter (e) -> e.custid is entry.custid
        if laps.length > 0
          laps = laps[0].laps
        else
          laps = 0
        if am.length > 0
          am = am[0].points
        else
          am = 0
        [
          name
          entry.irating
          if overall > 0 then overall else ''
          if am > 0 then am else ''
          laps
        ]
    rows.push []
    rows.push [
      "https://members.iracing.com/membersite/member/EventResult.do?&subsessionid=#{result.subsessionid}"
    ]
    excel_addsheet workbook, result.track_name, 'FF00FF00',
      Pilota : 50
      iRating: 20
      Overall : 8
      AM : 8
      'Giri Completati': 20
    , rows


  buffer = await workbook.xlsx.writeBuffer()
  fs.writeFileSync(path.parse(process.argv[2]).name + '.xlsx', buffer)

ir.login credentials.username, credentials.password, (loggedIn) ->
  if not loggedIn
    return console.error 'not logged in'
  util.listexec subsessionids, process_session, process_results


