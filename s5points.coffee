
rev = (a, b) -> b - a
sum = (a, b) -> a + b

class StandingsEntry
  constructor: (@custid, @name) ->
    @race_completed = 0
    @points = 0
    @position = 0
    @variation = 0
    @results = []

  add: (points, drop) ->
    @race_completed += 1
    @results.push points
    @points = @results.slice().sort(rev).slice(0, drop).reduce sum, 0

  setPosition: (pos) ->
    oldPos = @position
    @position = pos
    if oldPos isnt 0
      @variation = oldPos - pos

  toString: () -> "#{@custid}\t#{@race_completed}\t#{@points}\t#{@position} (#{@variation})\t#{@name}"

class S5PointsStandingsManager

  constructor: () ->
    @points_table = [
      40, 35, 30, 28, 26, 24, 22, 20, 18, 16,
      15, 14, 13, 12, 11, 10,  9,  8,  7,  6,
       5,  4,  3,  2,  1
    ]
    @standings_overall = []
    @standings_am = []

    @am_threshold = 2500
    @am_increment_tolerance = 500
    @am_week_until_verify_irating = 8
    @am_blacklist = []

    @official_start_min = 8
    @official_complete_min = 6

    @drop_overall = 8
    @drop_am = 6

    @complete_pct = 50

    @week_number = 0

  by_custid: (custid) -> (e) -> e.custid is custid

  is_in_standings: (custid) -> @standings_overall.filter(@by_custid(custid)).length > 0

  is_am_in_standings: (custid) -> @standings_am.filter(@by_custid(custid)).length > 0

  am_requires_removal: (custid, irating) -> irating > ( @am_threshold + @am_increment_tolerance )

  is_am: (custid, irating) ->
    if -1 isnt @am_blacklist.indexOf custid
      return no
    if @is_am_in_standings custid
      if @week_number <= @am_week_until_verify_irating
        if @am_requires_removal custid, irating
          return no
      return yes
    return irating < @am_threshold

  started_the_race: (row) -> row.laps > 0

  completed_required_percentage: (leader_laps, percentage) ->
    (row) -> row.laps > leader_laps * (percentage / 100)

  is_official: (rows) ->
    if rows.filter(@started_the_race).length < @official_start_min
      no
    else
      leader_laps = rows[0].laps
      rows.filter(@completed_required_percentage(leader_laps, @complete_pct)).length > @official_complete_min

  sort_by_points: (a,b) -> b.points - a.points

  add_race: (rows) ->
    @week_number += 1
    if not @is_official rows
      return
        official : no
        standings :
          overall : @standings_overall
          am : @standings_am

    leader_laps = rows[0].laps
    completed_fn = @completed_required_percentage leader_laps, @complete_pct
    standings_overall_race = rows.map (row, index) =>
      completed_race = completed_fn row
      return
        custid: row.custid
        name  : row.name
        irating : row.irating
        points: if completed_race and index < @points_table.length then @points_table[index] else 0

    standings_am_race = rows.filter((row) => @is_am(row.custid, row.irating)).map (row, index) =>
      completed_race = @completed_required_percentage(leader_laps, @complete_pct)(row)
      return
        custid: row.custid
        name  : row.name
        irating : row.irating
        points: if completed_race and index < @points_table.length then @points_table[index] else 0

    for entry in standings_overall_race
      if @is_in_standings entry.custid
        for oentry in @standings_overall
          if oentry.custid is entry.custid
            oentry.add entry.points, @drop_overall
      else
        oentry = new StandingsEntry entry.custid, entry.name
        oentry.add entry.points, @drop_overall
        @standings_overall.push oentry
    @standings_overall.sort @sort_by_points
    @standings_overall.forEach (entry, index) -> entry.setPosition index + 1

    for row in rows
      if @am_requires_removal(row.custid, row.irating)
        @standings_am = @standings_am.filter (e) -> e.custid isnt row.custid
        @am_blacklist.push row.custid


    for entry in standings_am_race
      if @is_am_in_standings(entry.custid)
        for oentry in @standings_am
          if oentry.custid is entry.custid
            oentry.add entry.points, @drop_am
      else
        oentry = new StandingsEntry entry.custid, entry.name
        oentry.add entry.points, @drop_am
        @standings_am.push oentry
    @standings_am.sort @sort_by_points
    @standings_am.forEach (entry, index) -> entry.setPosition index + 1

    return
      official : yes
      race:
        overall: standings_overall_race
        am : standings_am_race
      standings :
        overall : @standings_overall
        am : @standings_am

  recap: () ->
    console.log "Overall"
    @standings_overall.forEach (e) -> console.log "#{e}"
    console.log "AM"
    @standings_am.forEach (e) -> console.log "#{e}"

exports.S5PointsStandingsManager = S5PointsStandingsManager

