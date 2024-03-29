__includes [ "TreeFill.nls" "DDR-coin.nls" "CoinRand.nls" "RingRand.nls" "CT.nls" "utils.nls" ]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Global variables common to all DTC algorithms ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
globals [
  CUR_ROUND ; current round number
  GEN_TRIGGERS ; the number of generated triggers so far in go procedure
  NUM_EXCHANGED_MESSAGES ; the number of exchanged messages between nodes so far
  MAX_RCVD ; current maximum number of received messages at each node
  NUM_DETECTED_TRIGGERS ; total number of detected triggers by all the nodes so far
  W_HAT_LAST_ROUND ; not yet detected triggers when a round begins
  IS_END_OF_ROUND ; some DTC algos need this to make it work
  DEBUG_OUTPUT ; debug output level. 0 info, 1 debug, 2 trace
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Note on the relationship between node and algo in this simulation ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Netlogo is not an OOP language. There is no concept like a member function.
; But, breed is close to the object or class concept existing in many OOP languages.
;
; In this simulation, by using breed, defined 'nodes' and 'node' to implement set of node agents and individual node agent
; which is running a DTC algorithm. (Note that Netlogo uses turtle to represent an agent in a simulation)
; The node turtle has attributes to count the numbers of received triggers, received messages. It is also providing
; trigger aggregation for all the DTC algorithms running in this simulation.
;
; Each node runs a DTC algorithm. Using the simulation UI, you can select a DTC algorithm you want to run on a node.
; The DTC algorithm running on a node is implemented with intrinsic breed for each DTC algorithm. DTC algorithms are
; defined in separate files: TreeFill.nls, DDR-coin.nls, CoinRand.nls, RingRand.nls, and CT.nls.
;
; When a simulation is initialized, nodes are created and each node is associated with one DTC algorithm turtle.
; The algo-id in node is for binding a DTC algorithm turtle with a node. Setup-nodes command is doing the initialization.
; It internally calls create-one-algo with user selected DTC algorithm type, and it returns a new DTC algorithm turtle.
; Then, node and DTC algorithm turtles are related by having the id of each other.
;
; All the node interaction is done by exchanging messages. Send-message command is used to send a message to a node in a simulation.
; There are some messages understood at node level and handled by node; trigger-aggregation messages are handled by node so all the
; DTC algorithm simulation can share trigger-aggregation logic. Other message types are all different for the DTC algorithms.
; So, other than trigger-aggregation messages, all other messages are forwarded to DTC algorithm turtle. This part is implemented in
; handle-msg command.
;
; Each DTC algorithm file has logics to process specific message types for it. DTC algorithm turtles will exchange messages to detect
; when all the detected triggers by all the nodes in simulation reaches up until a predefined threshold for detected triggers is met.
breed [nodes node]
nodes-own [num-triggers num-received-msgs parent-id child-ids algo-id num-aggregate-responses aggregated-triggers]

; called when the setup button on the interface is clicked
to setup
  clear-all

  ; control debug output here
  set DEBUG_OUTPUT 0
  print (word "setup. num-nodes: " NUM-NODES)
  set NUM-NODES adjust-num-nodes
  print (word "adjusted num-nodes: " NUM-NODES)

  set CUR_ROUND 1
  set GEN_TRIGGERS 0
  set NUM_EXCHANGED_MESSAGES 0
  set MAX_RCVD 0
  set NUM_DETECTED_TRIGGERS 0
  set W_HAT_LAST_ROUND GIVEN-TRIGGERS
  set IS_END_OF_ROUND false

  setup-visual-settings
  setup-nodes
  setup-algos
  reset-ticks

  print (word "DTC algo: " DTC-ALGO)
  print (word "given triggers: " GIVEN-TRIGGERS)
  print "Start the first round"

  if result-file [
    file-open (word DTC-ALGO " " date-and-time ".txt")
    file-print (word "# algo: " DTC-ALGO ", num-nodes: " NUM-NODES ", given-triggers: " GIVEN-TRIGGERS)
    if DTC-ALGO = "DDR-coin" [
      file-print(word "# predeploying-const: " PREDEPLOYING-CONST)
    ]
    file-print "# round, NUM_EXCHANGED_MESSAGES, MAX_RCVD, w-hat, detected-triggers"
  ]
end

to end-of-round-update [w-hat]
  if result-file [
    file-print (word CUR_ROUND ", " NUM_EXCHANGED_MESSAGES ", " MAX_RCVD ", " W_HAT_LAST_ROUND ", " NUM_DETECTED_TRIGGERS)
  ]
  set W_HAT_LAST_ROUND w-hat
end

to-report adjust-num-nodes
  report (ifelse-value
    DTC-ALGO = "CoinRand" [ 2 ^ floor (log NUM-NODES 2) ]
    (DTC-ALGO = "TreeFill" or DTC-ALGO = "DDR-coin" or DTC-ALGO = "CT")
    [ TREE-ORDER ^ floor (log NUM-NODES TREE-ORDER) ]
    (DTC-ALGO = "RingRand")
    [ NUM-NODES ])
end

to setup-nodes
  create-nodes NUM-NODES [
    set num-triggers 0
    set num-received-msgs 0
    set child-ids (list)
    set num-aggregate-responses 0
    set aggregated-triggers 0
    set hidden? true
  ]
  ; parent-child relationship is for making tree for aggregation process happening at the end of some DTC algos.
  ; node 0's childs are 1 and 2. node 1's childs are 3 and 4. etc.
  let nid 0
  while [nid < NUM-NODES] [
    let pid floor ((nid - 1) / 2)
    ask node nid [set parent-id pid]
    if pid >= 0 [
      ask node pid [set child-ids lput nid child-ids]
    ]
    set nid (nid + 1)
  ]
  ; Let nodes and algos know each other's ids to make interaction easier.
  let next-id count nodes
  set nid 0
  while [nid < NUM-NODES] [
    ; create one new algo where the id of new algo begins at num-nodes.
    ; So, (node-algo) relations would be (0, num-nodes), (1, num-nodes + 1), ...
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
  DTC-ALGO = "CoinRand" [
      create-crnds 1 [
        set tau ceiling (GIVEN-TRIGGERS / (4 * NUM-NODES))
        set triggers-cnt 0
        set coins-cnt 0
        set color green
    ]
  ]
  DTC-ALGO = "RingRand" [
      create-rrnds 1 [
        set p_collect (8 * NUM-NODES / GIVEN-TRIGGERS)
        set color green
    ]
  ]
  DTC-ALGO = "TreeFill" [
      create-tfs 1 [
        set threshold floor (GIVEN-TRIGGERS / (2 * NUM-NODES))
        set triggers-cnt 0
        set fullary []
        let i 0
        while [i < TREE-ORDER] [
          set fullary lput 0 fullary
          set i i + 1
        ]
        set color green
      ]
   ]
  DTC-ALGO = "DDR-coin" [
      create-ddrcs 1 [
        set p_detect NUM-NODES / GIVEN-TRIGGERS
        set fullary []
        let i 0
        while [i < TREE-ORDER] [
          set fullary lput 0 fullary
          set i i + 1
        ]
        set color green
      ]
  ]
  DTC-ALGO = "CT" [
      create-csts 1 [
        set threshold floor(GIVEN-TRIGGERS / (2 * NUM-NODES))
        set triggers-cnt 0
        set detects-cnt 0
        set color green
      ]
  ])
end

to setup-algos
  (ifelse
  DTC-ALGO = "CoinRand" [setup-crnd-layers]
  DTC-ALGO = "RingRand" [setup-rrnd-topology]
  DTC-ALGO = "TreeFill" [setup-tf-layers]
  DTC-ALGO = "DDR-coin" [setup-ddrc-layers]
  DTC-ALGO = "CT"       [setup-cst-layers])
end

to go
  if NUM_DETECTED_TRIGGERS >= GIVEN-TRIGGERS [
    print (word "Simulation stopped. NUM_DETECTED_TRIGGERS: " NUM_DETECTED_TRIGGERS ", num-generated-triggers: " GEN_TRIGGERS)
    if result-file [
      file-close
    ]
    stop
  ]
  if (GEN_TRIGGERS < GIVEN-TRIGGERS) and (not IS_END_OF_ROUND) [
    ask one-of nodes [ handle-trigger ]
    set GEN_TRIGGERS (GEN_TRIGGERS + 1)
  ]
  tick
end

to handle-trigger
  set num-triggers (num-triggers + 1)
  (ifelse
  DTC-ALGO = "CoinRand" [
      ask crnd algo-id [handle-trigger-crnd]
  ]
  DTC-ALGO = "RingRand" [
      ask rrnd algo-id [handle-trigger-rrnd]
  ]
  DTC-ALGO = "TreeFill" [
      ask tf algo-id [handle-trigger-tf]
  ]
  DTC-ALGO = "DDR-coin" [
      ask ddrc algo-id [handle-trigger-ddrc]
  ]
  DTC-ALGO = "CT" [
      ask cst algo-id [handle-trigger-cst]
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
          set NUM_DETECTED_TRIGGERS (aggregated-triggers + num-triggers)
          ifelse is-log-level-debug [
            print (word "Aggregated triggers: " NUM_DETECTED_TRIGGERS ", debug aggregation: " aggregate-detected-triggers-for-debug)
          ] [
            print (word "Aggregated triggers: " NUM_DETECTED_TRIGGERS)
          ]

          let w-hat GIVEN-TRIGGERS - NUM_DETECTED_TRIGGERS
          end-of-round-update w-hat

          if w-hat <= 0 [
            print "DETECT ALL THE TRIGGERS!! stop simulation"
            stop
          ]
          (ifelse
            DTC-ALGO = "CoinRand" [ask crnd algo-id [handle-msg-crnd "initiate-next-round" (list w-hat)]]
            DTC-ALGO = "TreeFill" [ask tf algo-id [handle-msg-tf "initiate-next-round" (list w-hat)]]
            DTC-ALGO = "DDR-coin" [ask ddrc algo-id [handle-msg-ddrc "initiate-next-round" (list w-hat)]]
            DTC-ALGO = "CT"       [ask cst algo-id [handle-msg-cst "initiate-next-round" (list w-hat)]]
          )
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
        DTC-ALGO = "CoinRand" [ask crnd algo-id [handle-msg-crnd msg vals]]
        DTC-ALGO = "RingRand" [ask rrnd algo-id [handle-msg-rrnd msg vals]]
        DTC-ALGO = "TreeFill" [ask tf algo-id [handle-msg-tf msg vals]]
        DTC-ALGO = "DDR-coin" [ask ddrc algo-id [handle-msg-ddrc msg vals]]
        DTC-ALGO = "CT"       [ask cst algo-id [handle-msg-cst msg vals]])
    ]
  )
end

to send-message [to-id msg vals]
  if is-log-level-trace [
    print (word msg ": " to-id ", " vals)
  ]
  set NUM_EXCHANGED_MESSAGES (NUM_EXCHANGED_MESSAGES + 1)
  ask node to-id [
    set num-received-msgs (num-received-msgs + 1)
    if num-received-msgs > MAX_RCVD [
      set MAX_RCVD num-received-msgs
    ]
    handle-msg msg vals
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
263
14
781
333
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
DTC-ALGO
DTC-ALGO
"TreeFill" "DDR-coin" "CoinRand" "RingRand" "CT"
2

INPUTBOX
18
105
104
165
NUM-NODES
4096.0
1
0
Number

MONITOR
23
360
123
405
cur-round
CUR_ROUND
17
1
11

MONITOR
138
360
322
405
num-exchanged-messages
NUM_EXCHANGED_MESSAGES
17
1
11

INPUTBOX
18
179
126
239
TREE-ORDER
8.0
1
0
Number

TEXTBOX
134
181
239
228
TREE-ORDER is for TreeFill, DDR-coin, or CT
11
0.0
1

INPUTBOX
114
105
242
165
GIVEN-TRIGGERS
500000.0
1
0
Number

MONITOR
328
360
485
405
num-detected-triggers
NUM_DETECTED_TRIGGERS
17
1
11

PLOT
24
419
781
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
"Exchanged Messages" 1.0 0 -16777216 true "" "plot NUM_EXCHANGED_MESSAGES"
"DetectedTriggers" 1.0 0 -13345367 true "" "plot NUM_DETECTED_TRIGGERS"

MONITOR
503
360
595
405
max-rcvd
MAX_RCVD
17
1
11

INPUTBOX
17
252
157
312
PREDEPLOYING-CONST
3.0
1
0
Number

TEXTBOX
161
249
262
319
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
NetLogo 6.2.1
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
