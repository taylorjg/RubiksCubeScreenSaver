#  Description

A macOS screensaver of a Rubik's cube as it is being solved. This repo is written in Swift using Metal.

> **NOTE** Initially, I will be cheating - the "solving" process will just be undoing the moves used to scramble the cube.
However, I hope to implement a solving algorithm properly at a later date.

# TODO

* ~~Render a basic solved cube with flat shading~~
* Simplify/improve the assignment of colours to faces by adding materials to the model in Blender
  * This should result in a submesh per material when loading the model in Model I/O making it easier to assign colours
* ~~Implement the main logic~~
* ~~Render a scrambled cube~~
* ~~Render each step in the solving of the cube (not animated)~~
* ~~Animate each step in the solving of the cube~~
* ~~When solving is complete, pause then rescramble~~
* On each scramble, choose a random cube size and random number of scramble moves
* Implement ambient/diffuse/specular lighting
* Add a config sheet to the screensaver
  * Enabled cube sizes: 2, 3, 4, 5
  * Cycle between cube sizes in order or randomly choose next cube size
  * How long to pause showing the solved cube before re-scrambling/solving
* Add screensaver thumbnail  

# Links

* This repo is a port of one of my earlier projects written in JavaScript using three.js - repo [here](https://github.com/taylorjg/rubiks-cube)
