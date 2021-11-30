https = require 'https'

filecache = require './filecache'
logger = require './logger'

cache = new filecache.FileCache 'ir.cache'

cookiejar = {}

parse_cookies = (set_cookies) ->
  set_cookies.forEach (set_cookie) ->
    kv = set_cookie.split(/;/)[0].split(/=/)
    cookiejar[kv[0]] = kv[1]

hash_to_query = (params) ->
  query = []
  for key, value of params
    if typeof value is 'string' or typeof value is 'number'
      query.push "#{encodeURIComponent key}=#{encodeURIComponent value}"
    else
      for value_el in value
        query.push "#{encodeURIComponent key}=#{encodeURIComponent value_el}"
  query.join '&'

get_cookies = ->
  cookie = []
  for name, value of cookiejar
    cookie.push name + '=' + value
  cookie.join('; ')

exports.login = (username, password, callback) ->
  options =
    hostname : 'members.iracing.com'
    port : 443
    path : '/jforum/Login'
    method : 'post'
    headers:
      'Content-Type' : 'application/x-www-form-urlencoded'
  body = "username=#{encodeURIComponent username}&password=#{encodeURIComponent password}"
  req = https.request options, (res) ->
    parse_cookies res.headers['set-cookie']
    if res.headers['location'] is 'https://members.iracing.com/jforum'
      callback yes
    else
      callback no
  req.write body
  req.end()

get = (path, callback) ->
  key = "request.GET.#{path}"
  cache.get key, (5 * 24 * 60 * 60 * 1000), (found, response) ->
    if found
      callback response.statusCode, response.body
      return
    setTimeout ->
      logger.log 'GET', path
      options =
        hostname: 'members.iracing.com'
        port: 443
        path : path
        method: 'get'
        headers:
          cookie: get_cookies()
      req = https.request options, (res) ->
        parse_cookies res.headers['set-cookie']
        chunks = []
        res.on 'data', (chunk) -> chunks.push chunk
        res.on 'end', ->
          if res.statusCode is 200
            cache.put key, {
              statusCode: res.statusCode
              body: chunks.join('')
            }, ->
              callback res.statusCode, chunks.join('')
          else
            callback res.statusCode, chunks.join('')
      req.end()
    , 2000

post = (path, params, callback) ->
  key = "request.POST.#{path}.#{hash_to_query params}"
  cache.get key, (7 * 24 * 60 * 60 * 1000), (found, response) ->
    if found
      callback response.statusCode, response.body
      return
    setTimeout ->
      logger.log 'POST', path
      body = hash_to_query params
      logger.log '\t', body
      options =
        hostname: 'members.iracing.com'
        port: 443
        path : path
        method: 'post'
        headers:
          cookie: get_cookies()
          'Content-Type': 'application/x-www-form-urlencoded'
      req = https.request options, (res) ->
        parse_cookies res.headers['set-cookie']
        chunks = []
        res.on 'data', (chunk) -> chunks.push chunk
        res.on 'end', ->
          if res.statusCode is 200
            cache.put key, {
              statusCode: res.statusCode
              body: chunks.join('')
            }, ->
              callback res.statusCode, chunks.join('')
          else
            callback res.statusCode, chunks.join('')
      req.write body
      req.end()
    , 2000

get_chart_data = exports.get_chart_data = (custid, catid, chartType, callback) ->
  path = "/memberstats/member/GetChartData?custId=#{custid}&catId=#{catid}&chartType=#{chartType}"
  get path, (statuscode, body) ->
    result = JSON.parse body
    callback result

get_subsession_results = exports.get_subsession_results = (subsessionid, callback) ->
  params =
    subsessionID: subsessionid
  post '/membersite/member/GetSubsessionResults', params, (statuscode, body) ->
    callback JSON.parse body

get_results = exports.get_results = (params, callback) ->
  defaultParams =
    showraces: 1
    showquals: 0
    showops: 0
    showofficial: 1
    showunofficial: 0
    showrookie: 1
    showclassd: 1
    showclassc: 1
    showclassb: 1
    showclassa: 1
    showpro: 1
    showprowc: 1
    lowerbound: 0
    upperbound: 25
    sort: 'start_time'
    order: 'desc'
    format: 'json'
    'category[]': [1,2,3,4]
  for key, value of params
    defaultParams[key] = value
  path = "/memberstats/member/GetResults?#{hash_to_query defaultParams}"
  # logger.log path
  get path, (statuscode, result) ->
    callback JSON.parse result

calculate_sof = exports.calculate_sof = (iratings) ->
  c = 1600 / Math.log 2
  s = iratings.map (ir) -> Math.exp -ir/c
  s_sum = s.reduce (a,b) -> a + b
  return parseInt c * Math.log iratings.length / s_sum

exports.calculate_points = (iratings) ->
  sof = calculate_sof iratings
  n = iratings.length
  positions = iratings.map (el, idx) -> idx + 1
  results = positions.map (p) ->
    if p is 1
      if n is 1
        0.5 * 1.06 * sof / 16
      else
        n / (n+1) * 1.06 * sof / 16 * (n - p) / (n - 1)
    else
      if p is n
        n / (n+1) * 1.06 * sof / 16 * (n - (p - 1)) / (n - 1) / 2
      else
        (n / (n+1) * 1.06 * sof / 16 * (n - p) / (n - 1))
  results.map (pts) -> parseInt pts

exports.get_irating_at_time = (custid, catid, date_compare_long, callback) ->
  # logger.log 'ricerca risultati successivi al ', new Date(date_compare_long)
  get_chart_data custid, catid, 1, (irating_graph) ->
    last = 1350
    last_time = 0
    for row in irating_graph
      time = row[0]
      irating = row[1]
      # logger.log irating, new Date(time), ' >= ', new Date(date_compare_long)
      if time >= date_compare_long
        # logger.log 'trovato risultato successivo al ', new Date(date_compare_long)
        # logger.log 'cerco result dal', new Date(last_time), ' al ', new Date(date_compare_long)
        get_results {
          custid: custid
          starttime_low : last_time
          starttime_high: date_compare_long
          upperbound: 25
          'category[]' : [catid]
        }, (results) ->
          if results and results.d and results.d.r and results.d.r.length > 0
            # logger.log 'lista results', results.d.r.map (r) -> { d: new Date(r[11]), s: r[41] }
            result = null
            for result in results.d.r
              if result[11] < date_compare_long
                break
            if result[11] >= date_compare_long
              return callback last, 'graph', null, new Date(last_time)
            subsessionid = result[41]
            # logger.log 'ultima subsession per il filtro ', subsessionid
            get_subsession_results subsessionid, (results) ->
              myrow = results.rows.filter (row) ->
                row.custid is custid and row.simsesname is 'RACE'
              myrow = myrow[0]
              # logger.log 'riga del result', myrow
              callback myrow.newirating, 'subsession', subsessionid, new Date myrow.subsessionfinishedat
          else
            callback last, 'graph', null, new Date last_time
        return
      last = irating
      last_time = time
    # logger.log 'ultimo risultato', last, ' del ', new Date(last_time)
    callback last, 'graph', null, new Date last_time


