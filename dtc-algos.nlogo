__includes [ "TreeFill.nls" "DDR-coin.nls" "CoinRand.nls" "RingRand.nls" ]

globals [
  cur-round ; current round number
  gen-triggers ; the number of generated triggers so far in go procedure
  num-exchanged-messages ; the number of exchanged messages between nodes so far
  max-rcvd ; current maximum number of received messages at each node
  num-detected-triggers ; total number of detected triggers by all the nodes so far
  w-hat-last-round ; not yet detected triggers when a round begins
  is-end-of-round ; some DTC algos need this to make it work
  debug-output ; debug output level. 0 info, 1 debug, 2 trace
]

breed [nodes node]
nodes-own [num-triggers num-received-msgs parent-id child-ids algo-id num-aggregate-responses aggregated-triggers]


to setup
  clear-all

  ; control debug output here
  set debug-output 0
  print (word "setup. num-nodes: " num-nodes)
  set num-nodes adjust-num-nodes
  print (word "adjusted num-nodes: " num-nodes)

  set cur-round 1
  set gen-triggers 0
  set num-exchanged-messages 0
  set max-rcvd 0
  set num-detected-triggers 0
  set w-hat-last-round given-triggers
  set is-end-of-round false

  setup-visuals
  setup-nodes
  setup-algos
  reset-ticks

  print (word "DTC algo: " dtc-algo)
  print (word "given triggers: " given-triggers)
  print "Start the first round"

  if result-file [
    file-open (word dtc-algo " " date-and-time ".txt")
    file-print (word "# algo: " dtc-algo ", num-nodes: " num-nodes ", given-triggers: " given-triggers)
    if dtc-algo = "DDR-coin" [
      file-print(word "# predeploying-const: " predeploying-const)
    ]
    file-print "# round, num-exchanged-messages, max-rcvd, w-hat, detected-triggers"
  ]
end

to end-of-round-update [w-hat]
  if result-file [
    file-print (word cur-round ", " num-exchanged-messages ", " max-rcvd ", " w-hat-last-round ", " num-detected-triggers)
  ]
  set w-hat-last-round w-hat
end

to-report is-log-level-info
  report debug-output >= 0
end

to-report is-log-level-debug
  report debug-output >= 1
end

to-report is-log-level-trace
  report debug-output >= 2
end

to-report adjust-num-nodes
  report (ifelse-value
    dtc-algo = "CoinRand" [ 2 ^ floor (log num-nodes 2) ]
    (dtc-algo = "TreeFill" or dtc-algo = "DDR-coin")
    [ tree-order ^ floor (log num-nodes tree-order) ]
    (dtc-algo = "RingRand")
    [ num-nodes ])
end

to setup-visuals
  set-default-shape crnds "circle"
  set-default-shape rrnds "circle"
  set-default-shape tfs "circle"
  set-default-shape ddrcs "circle"
  ask patches [
    set pcolor white
    set plabel-color black
  ]
end

to setup-nodes
  create-nodes num-nodes [
    set num-triggers 0
    set num-received-msgs 0
    set child-ids (list)
    set num-aggregate-responses 0
    set aggregated-triggers 0
    set hidden? true
  ]
  ; parent-child relationship is for making tree for aggregation process happening at the end of some DTC algos.
  let nid 0
  while [nid < num-nodes] [
    let pid floor ((nid - 1) / 2)
    ask node nid [set parent-id pid]
    if pid >= 0 [
      ask node pid [set child-ids lput nid child-ids]
    ]
    set nid (nid + 1)
  ]
  ; having node and algo know each other's ids to make interaction easier.
  let next-id count nodes
  set nid 0
  while [nid < num-nodes] [
    create-one-algo
    ask node nid [set algo-id next-id]
    ask turtle [algo-id] of (node nid) [set node-id nid]
    set next-id (next-id + 1)
    set nid (nid + 1)
  ]
  if is-log-level-debug [
    ask nodes [
      print (word who ": algo-id(" algo-id "), child-ids" child-ids ", parent-id(" parent-id ")")
    ]
  ]
end

to create-one-algo
  (ifelse
  dtc-algo = "CoinRand" [
      create-crnds 1 [
        set tau ceiling (given-triggers / (4 * num-nodes))
        set triggers-cnt 0
        set coins-cnt 0
        set color green
    ]
  ]
  dtc-algo = "RingRand" [
      create-rrnds 1 [
        set p_collect (8 * num-nodes / given-triggers)
        set color green
    ]
  ]
  dtc-algo = "TreeFill" [
      create-tfs 1 [
        set threshold floor (given-triggers / (2 * num-nodes))
        set triggers-cnt 0
        set fullary []
        let i 0
        while [i < tree-order] [
          set fullary lput 0 fullary
          set i i + 1
        ]
        set color green
      ]
   ]
  dtc-algo = "DDR-coin" [
      create-ddrcs 1 [
        set p_detect num-nodes / given-triggers
        set fullary []
        let i 0
        while [i < tree-order] [
          set fullary lput 0 fullary
          set i i + 1
        ]
        set color green
      ]
  ])
end

to setup-algos
  (ifelse
  dtc-algo = "CoinRand" [setup-crnd-layers]
  dtc-algo = "RingRand" [setup-rrnd-topology]
  dtc-algo = "TreeFill" [setup-tf-layers]
  dtc-algo = "DDR-coin" [setup-ddrc-layers])
end

to go
  if num-detected-triggers >= given-triggers [
    print (word "Simulation stopped. num-detected-triggers: " num-detected-triggers ", num-generated-triggers: " gen-triggers)
    if result-file [
      file-close
    ]
    stop
  ]
  if (gen-triggers < given-triggers) and (not is-end-of-round) [
    ask one-of nodes [ handle-trigger ]
    set gen-triggers (gen-triggers + 1)
  ]
  tick
end

to handle-trigger
  set num-triggers (num-triggers + 1)
  (ifelse
  dtc-algo = "CoinRand" [
      ask crnd algo-id [handle-trigger-crnd]
  ]
  dtc-algo = "RingRand" [
      ask rrnd algo-id [handle-trigger-rrnd]
  ]
  dtc-algo = "TreeFill" [
      ask tf algo-id [handle-trigger-tf]
  ]
  dtc-algo = "DDR-coin" [
      ask ddrc algo-id [handle-trigger-ddrc]
  ])
end

to handle-msg [msg vals]
  (ifelse
    msg = "aggregate-triggers" [
      if is-log-level-trace [ print (word "Aggregate triggers at " who) ]
      ifelse empty? child-ids [
        send-message parent-id "aggregate-triggers-response" (list num-triggers)
      ] [
        foreach child-ids [
          cid -> send-message cid "aggregate-triggers" []
        ]
      ]
    ]
    msg = "aggregate-triggers-response" [
      let aggregate-children item 0 vals
      if is-log-level-trace [ print (word "Received aggregate-triggers-response at " who " with " aggregate-children) ]
      set num-aggregate-responses (num-aggregate-responses + 1)
      set aggregated-triggers (aggregated-triggers + aggregate-children)
      if num-aggregate-responses >= length child-ids [
        ifelse (parent-id < 0) [
          if is-log-level-debug [
            print (word "Aggregated triggers at the root: " (aggregated-triggers + num-triggers) " (children: " aggregated-triggers ", root: " num-triggers ")")
          ]
          set num-detected-triggers (aggregated-triggers + num-triggers)
          ifelse is-log-level-debug [
            print (word "Aggregated triggers: " num-detected-triggers ", debug aggregation: " aggregate-detected-triggers-for-debug)
          ] [
            print (word "Aggregated triggers: " num-detected-triggers)
          ]

          let w-hat given-triggers - num-detected-triggers
          end-of-round-update w-hat

          if w-hat <= 0 [
            print "DETECT ALL THE TRIGGERS!! stop simulation"
            stop
          ]
          (ifelse
            dtc-algo = "CoinRand" [ask crnd algo-id [handle-msg-crnd "initiate-next-round" (list w-hat)]]
            dtc-algo = "TreeFill" [ask tf algo-id [handle-msg-tf "initiate-next-round" (list w-hat)]]
            dtc-algo = "DDR-coin" [ask ddrc algo-id [handle-msg-ddrc "initiate-next-round" (list w-hat)]])
        ] [
          send-message parent-id "aggregate-triggers-response" (list (aggregated-triggers + num-triggers))
        ]
        set num-aggregate-responses 0
        set aggregated-triggers 0
      ]
    ]
    ; DTC algo specific messages
    [
      (ifelse
        dtc-algo = "CoinRand" [ask crnd algo-id [handle-msg-crnd msg vals]]
        dtc-algo = "RingRand" [ask rrnd algo-id [handle-msg-rrnd msg vals]]
        dtc-algo = "TreeFill" [ask tf algo-id [handle-msg-tf msg vals]]
        dtc-algo = "DDR-coin" [ask ddrc algo-id [handle-msg-ddrc msg vals]])
    ]
  )
end

to send-message [to-id msg vals]
  ; this will make too many logs. manually uncomment this when trace-level degugging is required
  ;print (word msg ": " to-id ", " vals)
  set num-exchanged-messages (num-exchanged-messages + 1)
  ask node to-id [
    set num-received-msgs (num-received-msgs + 1)
    if num-received-msgs > max-rcvd [
      set max-rcvd num-received-msgs
    ]
    handle-msg msg vals
  ]
end

to-report aggregate-detected-triggers-for-debug
  let tot-trgs 0
  ask nodes [
    set tot-trgs (tot-trgs + num-triggers)
  ]
  report tot-trgs
end
@#$#@#$#@
GRAPHICS-WINDOW
251
11
769
330
-1
-1
10.0
1
10
1
1
1
0
1
1
1
-25
25
-15
15
1
1
1
ticks
30.0

BUTTON
17
14
72
47
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
75
15
130
48
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
17
50
155
95
dtc-algo
dtc-algo
"TreeFill" "DDR-coin" "CoinRand" "RingRand"
1

INPUTBOX
18
105
94
165
num-nodes
16.0
1
0
Number

MONITOR
23
360
123
405
cur-round
cur-round
17
1
11

MONITOR
138
360
309
405
NIL
num-exchanged-messages
17
1
11

INPUTBOX
18
179
126
239
tree-order
2.0
1
0
Number

TEXTBOX
134
181
239
228
Detect-tree-degree is only for TreeFill or DDR-coin
11
0.0
1

INPUTBOX
99
105
242
165
given-triggers
10000.0
1
0
Number

MONITOR
328
360
485
405
num-detected-triggers
num-detected-triggers
17
1
11

PLOT
24
419
766
657
The Number of Exchanged Messages and Detected Triggers
tick
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Exchanged Messages" 1.0 0 -16777216 true "" "plot num-exchanged-messages"
"DetectedTriggers" 1.0 0 -13345367 true "" "plot num-detected-triggers"

MONITOR
503
360
595
405
max-rcvd
max-rcvd
17
1
11

INPUTBOX
17
252
126
312
predeploying-const
2.0
1
0
Number

TEXTBOX
132
245
243
315
DDR-coin predeploys some detect messages at the begining of each round.
11
0.0
1

SWITCH
134
16
248
49
result-file
result-file
1
1
-1000

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
