S5PointsStandingsManager = (require './s5points').S5PointsStandingsManager

manager = new S5PointsStandingsManager

manager.add_race [
  {custid: 1, irating: 7000, laps: 5},
  {custid: 2, irating: 5500, laps: 5},
  {custid: 3, irating: 4500, laps: 5},
  {custid: 4, irating: 2400, laps: 4},
  {custid: 5, irating: 2600, laps: 4},
  {custid: 6, irating: 1800, laps: 4},
  {custid: 7, irating: 1600, laps: 4},
  {custid: 8, irating: 1700, laps: 4}
]

manager.recap()

manager.add_race [
  {custid: 2, irating: 6000, laps: 5},
  {custid: 1, irating: 2200, laps: 5}, # entra in classifica AM da qui
  {custid: 3, irating: 3800, laps: 4},
  {custid: 8, irating: 2000, laps: 4},
  {custid: 9, irating: 3500, laps: 4},
  {custid: 5, irating: 2200, laps: 4},
  {custid: 4, irating: 4500, laps: 4}, # rimosso da classifica AM
  {custid: 6, irating: 1900, laps: 3}
]

manager.recap()

manager.add_race [
  {custid: 1, irating: 6000, laps: 5},
  {custid: 2, irating: 6500, laps: 5},
  {custid: 4, irating: 2100, laps: 5}, # non deve tornare AM
  {custid: 3, irating: 4500, laps: 5},
  {custid: 7, irating: 6000, laps: 5},
  {custid: 6, irating: 6000, laps: 5},
  {custid: 8, irating: 6000, laps: 5},
  {custid: 5, irating: 6000, laps: 5},
  {custid: 9, irating: 6000, laps: 5},
]


manager.recap()
