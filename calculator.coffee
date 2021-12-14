
fs = require 'fs'
path = require 'path'
ir = require './ir'
logger = require './logger'
util = require './util'
filecache = require './filecache'
track_names = require './track-names'

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

filter_laps = (rows) ->
  leaderlaps = rows[0].laps
  limit = parseInt leaderlaps / 2
  rows.filter (row) ->
    # logger.log row.laps, limit, row.laps > limit
    row.incs_counted = row.laps >= leaderlaps - 1
    row.laps > limit

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
    res.rows_pts = filter_laps res.rows
    util.listexec res.rows_pts, get_irating_for_row, (rows) ->
      res.rows_pts = rows
      res.sof = ir.calculate_sof rows.map (row) -> row.irating
      points = ir.calculate_points rows.map (row) -> row.irating
      for row,i in rows
        row.points = points[i]
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

process_results = (results) ->
  for result in results
    logger.log result.track_name, result.start_time, result.sof
    for row in result.rows
      logger.log tab, row.name, tab, row.irating, tab, row.laps, tab, row.incidents, tab, row.end_time, row.points
  drivers = {}
  for result in results
    for row in result.rows_pts
      if drivers[row.name]
        drivers[row.name].points.push if row.points then row.points else 0
        drivers[row.name].points_races += if row.points then 1 else 0
        if row.incs_counted
          drivers[row.name].incs.push row.incidents
          drivers[row.name].incs_races += 1
      else
        drivers[row.name] =
          name: row.name
          points: [ if row.points then row.points else 0 ]
          points_races: if row.points then 1 else 0
          incs: [ if row.incs_counted then row.incidents else 0 ]
          incs_races: if row.incs_counted then 1 else 0


  pts_chart = clone(Object.values(drivers)).sort (a,b) -> util.sum(util.sort(b.points, util.desc).slice(0,8)) - util.sum(util.sort(a.points, util.desc).slice(0,8))
  logger.log 'Classifica punti'
  for row in pts_chart
    row.points_sum = util.sum util.sort(row.points, util.desc).slice(0,8)
    logger.log tab, row.name, tab, row.points_sum, tab, row.points_races

  incs_chart = clone(Object.values(drivers)).filter((d) -> d.incs_races > 0).sort incs_sort
  logger.log 'Classifica fair-play'
  for row in incs_chart
    row.incs_sum = util.sum util.sort(row.incs, util.asc).slice(0,8)
    row.incs_ratio = (row.incs_sum / Math.min(row.incs_races, 8)).toFixed 2
    logger.log tab, row.name, tab, row.incs_sum, tab, row.incs_races, tab, row.incs_ratio

  # prepara output
  workbook = new ExcelJS.Workbook()
  workbook.creator = 'dgdevel'
  sheet = workbook.addWorksheet 'Classifiche', {properties: {tabColor:{argb:'FFFF0000'}}}
  sheet.columns = [
    { header : 'Pilota', width: 50 }
    { header : 'Punti', width: 8 }
    { header : 'Gare Disputate', width: 15 }
    { header : ' ', width: 15 }
    { header : 'Pilota', width: 50 }
    { header : 'Incidenti', width: 8 }
    { header : 'Gare Disputate', width: 15 }
  ]
  for row, index in pts_chart
    incrow = incs_chart[index]

    sheet.getRow(index+2).getCell(1).value = fix_names row.name
    sheet.getRow(index+2).getCell(2).value = row.points_sum
    sheet.getRow(index+2).getCell(3).value = row.points_races + '/8'

    if incrow
      sheet.getRow(index+2).getCell(5).value = fix_names incrow.name
      sheet.getRow(index+2).getCell(6).value = incrow.incs_sum
      sheet.getRow(index+2).getCell(7).value = incrow.incs_races + '/8'
  sheet.getRow(index+3).getCell(1).value = 'Migliori 8 di 12 gare per la classifica a punti, richiesti 50% dei giri del leader'
  sheet.getRow(index+4).getCell(1).value = 'Migliori 8 di 12 gare per classifica fair play, richiesti max -1 giri dal leader'

  ptssheet = workbook.addWorksheet 'Dettaglio Punti', {properties: {tabColor:{argb:'FFFF0000'}}}
  ptssheet.columns = [
    { header: 'Pilota', width: 50 }
    { header: 'Punti', width: 8 }
    { header: 'Gare Disputate', width: 15 }
    { header: 'Dettaglio', width: 250 }
  ]
  for row, index in pts_chart
    ptssheet.getRow(index+2).getCell(1).value = fix_names row.name
    ptssheet.getRow(index+2).getCell(2).value = row.points_sum
    ptssheet.getRow(index+2).getCell(3).value = row.points_races + '/8'
    ptssheet.getRow(index+2).getCell(4).value = row.points.join(', ')


  incssheet = workbook.addWorksheet 'Dettaglio Incs', {properties: {tabColor: {argb: 'FFFF0000'}}}
  incssheet.columns = [
    { header : 'Pilota', width: 50 }
    { header : 'Incidenti', width: 8 }
    { header : 'Gare Disputate', width: 15 }
    { header : 'Dettaglio', width: 250 }
  ]
  for incrow, index in incs_chart
    incssheet.getRow(index+2).getCell(1).value = fix_names incrow.name
    incssheet.getRow(index+2).getCell(2).value = incrow.incs_sum
    incssheet.getRow(index+2).getCell(3).value = incrow.incs_races + '/8'
    incssheet.getRow(index+2).getCell(4).value = incrow.incs.join(', ')

  for result in results
    racesheet = workbook.addWorksheet result.track_name, {properties: {tabColor:{argb:'FF00FF00'}}}
    racesheet.columns = [
      { header: 'Pilota', width: 50 }
      { header: 'iRating', width: 8 }
      { header: 'Giri completati', width: 8 }
      { header: 'Punti', width: 8 }
      { header: 'Incidenti', width: 8 }
    ]
    for row, index in result.rows
      racesheet.getRow(index+2).getCell(1).value = fix_names row.name
      racesheet.getRow(index+2).getCell(2).value = row.irating
      racesheet.getRow(index+2).getCell(3).value = row.laps
      racesheet.getRow(index+2).getCell(4).value = row.points
      racesheet.getRow(index+2).getCell(5).value = row.incidents
    racesheet.getRow(index+3).getCell(3).value = 'SoF'
    racesheet.getRow(index+3).getCell(4).value = result.sof
    racesheet.getRow(index+4).getCell(1).value = "https://members.iracing.com/membersite/member/EventResult.do?&subsessionid=#{result.subsessionid}"

  buffer = await workbook.xlsx.writeBuffer()
  fs.writeFileSync(path.parse(process.argv[2]).name + '.xlsx', buffer)



ir.login credentials.username, credentials.password, (loggedIn) ->
  if not loggedIn
    return console.error 'not logged in'
  util.listexec subsessionids, process_session, process_results


