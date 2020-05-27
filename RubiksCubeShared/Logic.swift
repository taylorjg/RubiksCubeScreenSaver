//
//  Logic.swift
//  RubiksCubeShared
//
//  Created by Administrator on 27/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation

struct Faces {
    let up: Bool
    let down: Bool
    let left: Bool
    let right: Bool
    let front: Bool
    let back: Bool
}

func makeFaces(cubeDimensions: CubeDimensions, coords: Coords) -> Faces {
    return Faces(up: coords.y == cubeDimensions.vmax,
                 down: coords.y == cubeDimensions.vmin,
                 left: coords.x == cubeDimensions.vmin,
                 right: coords.x == cubeDimensions.vmax,
                 front: coords.z == cubeDimensions.vmin,
                 back: coords.z == cubeDimensions.vmax)
}

struct SolvedCubePiece {
    let coords: Coords
    let faces: Faces
}

func makeSolvedCube(cubeSize: Int) -> [SolvedCubePiece] {
    let cubeDimensions = getCubeDimensions(cubeSize: cubeSize)
    let allCoordsList = allCoords(cubeSize: cubeSize)
    return allCoordsList.map { coords in
        let faces = makeFaces(cubeDimensions: cubeDimensions, coords: coords)
        return SolvedCubePiece(coords: coords, faces: faces)
    }
}
